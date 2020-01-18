//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import DistributedActors
import DistributedActorsTestKit
import XCTest

final class MembershipTests: XCTestCase {
    let firstMember = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "1.1.1.1", port: 7337), nid: .random()), status: .up)
    let secondMember = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "2.2.2.2", port: 8228), nid: .random()), status: .up)
    let thirdMember = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "3.3.3.3", port: 9119), nid: .random()), status: .up)
    let newMember = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "4.4.4.4", port: 1001), nid: .random()), status: .up)

    lazy var initialMembership: Cluster.Membership = [
        firstMember, secondMember, thirdMember,
    ]
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: status ordering

    func test_status_ordering() {
        Cluster.MemberStatus.joining.shouldBeLessThanOrEqual(.joining)
        Cluster.MemberStatus.joining.shouldBeLessThan(.up)
        Cluster.MemberStatus.joining.shouldBeLessThan(.down)
        Cluster.MemberStatus.joining.shouldBeLessThan(.leaving)
        Cluster.MemberStatus.joining.shouldBeLessThan(.removed)

        Cluster.MemberStatus.up.shouldBeLessThanOrEqual(.up)
        Cluster.MemberStatus.up.shouldBeLessThan(.down)
        Cluster.MemberStatus.up.shouldBeLessThan(.leaving)
        Cluster.MemberStatus.up.shouldBeLessThan(.removed)

        Cluster.MemberStatus.leaving.shouldBeLessThanOrEqual(.leaving)
        Cluster.MemberStatus.leaving.shouldBeLessThan(.down)
        Cluster.MemberStatus.leaving.shouldBeLessThan(.removed)

        Cluster.MemberStatus.down.shouldBeLessThanOrEqual(.down)
        Cluster.MemberStatus.down.shouldBeLessThan(.removed)

        Cluster.MemberStatus.removed.shouldBeLessThanOrEqual(.removed)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: age ordering

    func test_age_ordering() {
        let ms = [
            Cluster.Member(node: firstMember.node, status: .joining),
            Cluster.Member(node: firstMember.node, status: .up, upNumber: 1),
            Cluster.Member(node: firstMember.node, status: .down, upNumber: 4),
            Cluster.Member(node: firstMember.node, status: .up, upNumber: 2),
        ]
        let ns = ms.sorted(by: Cluster.Member.ageOrdering).map { $0.upNumber }
        ns.shouldEqual([nil, 1, 2, 4])
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Member lookups

    func test_member_forNonUniqueNode() {
        var membership: Cluster.Membership = [firstMember, secondMember]
        var secondReplacement = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "2.2.2.2", port: 8228), nid: .random()), status: .up)

        let change = membership.join(secondReplacement.node)
        change.isReplacement.shouldBeTrue()

        membership.members(self.secondMember.node.node).count.shouldEqual(2)

        let mostUpToDateNodeAboutGivenNode = membership.firstMember(self.secondMember.node.node)
        mostUpToDateNodeAboutGivenNode.shouldEqual(secondReplacement)

        let nonUniqueNode = self.secondMember.node.node
        let seconds = membership.members(nonUniqueNode)

        // the current status of members should be the following by now:

        secondReplacement.status = .down
        seconds.shouldEqual([secondReplacement, secondMember]) // first the replacement, then the (now down) previous incarnation
    }

    func test_member_forNonUniqueNode_givenReplacementNodeStored() {}

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Applying changes

    func test_apply_LeadershipChange() throws {
        var membership = self.initialMembership
        membership.isLeader(self.firstMember).shouldBeFalse()

        let change = try membership.applyLeadershipChange(to: self.firstMember)
        change.shouldEqual(Cluster.LeadershipChange(oldLeader: nil, newLeader: self.firstMember))
        membership.isLeader(self.firstMember).shouldBeTrue()

        // applying "same change" no-op
        let noChange = try membership.applyLeadershipChange(to: self.firstMember)
        noChange.shouldBeNil()

        // changing to no leader is ok
        let noLeaderChange = try membership.applyLeadershipChange(to: nil)
        noLeaderChange.shouldEqual(Cluster.LeadershipChange(oldLeader: self.firstMember, newLeader: nil))

        do {
            _ = try membership.applyLeadershipChange(to: self.newMember) // not part of membership (!)
        } catch {
            "\(error)".shouldStartWith(prefix: "nonMemberLeaderSelected")
        }
    }

    func test_join_memberReplacement() {
        var membership = self.initialMembership

        let replacesFirstNode = UniqueNode(node: Node(systemName: "System", host: "1.1.1.1", port: 7337), nid: .random())

        let change = membership.join(replacesFirstNode)

        change.isReplacement.shouldBeTrue()
        change.replaced.shouldEqual(self.firstMember)
        change.replaced!.status.shouldEqual(self.firstMember.status)
        change.node.shouldEqual(replacesFirstNode)
        change.toStatus.shouldEqual(.joining)
    }

    func test_apply_memberReplacement() throws {
        var membership = self.initialMembership

        let firstReplacement = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "1.1.1.1", port: 7337), nid: .random()), status: .up)

        try shouldNotThrow {
            guard let change = membership.apply(Cluster.MembershipChange(member: firstReplacement)) else {
                throw TestError("Expected a change, but didn't get one")
            }

            change.isReplacement.shouldBeTrue()
            change.replaced.shouldEqual(self.firstMember)
            change.replaced!.status.shouldEqual(self.firstMember.status)
            change.node.shouldEqual(firstReplacement.node)
            change.toStatus.shouldEqual(firstReplacement.status)
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: member listing

    func test_members_listing() {
        self.initialMembership.members(atLeast: .joining).count.shouldEqual(3)
        self.initialMembership.members(atLeast: .up).count.shouldEqual(3)
        var changed = self.initialMembership
        _ = changed.mark(self.firstMember.node, as: .down)
        changed.count(atLeast: .joining).shouldEqual(3)
        changed.count(atLeast: .up).shouldEqual(3)
        changed.count(atLeast: .leaving).shouldEqual(1)
        changed.count(atLeast: .down).shouldEqual(1)
        changed.count(atLeast: .removed).shouldEqual(0)
    }

    func test_members_listing_filteringByReachability() {
        var changed = self.initialMembership
        _ = changed.mark(self.firstMember.node, as: .down)

        _ = changed.mark(self.firstMember.node, reachability: .unreachable)
        _ = changed.mark(self.secondMember.node, reachability: .unreachable)

        // exact status match

        changed.members(withStatus: .joining).count.shouldEqual(0)
        changed.members(withStatus: .up).count.shouldEqual(2)
        changed.members(withStatus: .down).count.shouldEqual(1)
        changed.members(withStatus: .leaving).count.shouldEqual(0)
        changed.members(withStatus: .removed).count.shouldEqual(0)

        changed.members(withStatus: .joining, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .up, reachability: .reachable).count.shouldEqual(1)
        changed.members(withStatus: .down, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .leaving, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .removed, reachability: .reachable).count.shouldEqual(0)

        changed.members(withStatus: .joining, reachability: .unreachable).count.shouldEqual(0)
        changed.members(withStatus: .up, reachability: .unreachable).count.shouldEqual(1)
        changed.members(withStatus: .down, reachability: .unreachable).count.shouldEqual(1)
        changed.members(withStatus: .leaving, reachability: .unreachable).count.shouldEqual(0)
        changed.members(withStatus: .removed, reachability: .unreachable).count.shouldEqual(0)

        // at-least status match

        changed.members(atLeast: .joining, reachability: .reachable).count.shouldEqual(1)
        changed.members(atLeast: .up, reachability: .reachable).count.shouldEqual(1)
        changed.members(atLeast: .down, reachability: .reachable).count.shouldEqual(0)
        changed.members(atLeast: .leaving, reachability: .reachable).count.shouldEqual(0)
        changed.members(atLeast: .removed, reachability: .reachable).count.shouldEqual(0)

        changed.members(atLeast: .joining, reachability: .unreachable).count.shouldEqual(2)
        changed.members(atLeast: .up, reachability: .unreachable).count.shouldEqual(2)
        changed.members(atLeast: .leaving, reachability: .unreachable).count.shouldEqual(1)
        changed.members(atLeast: .down, reachability: .unreachable).count.shouldEqual(1)
        changed.members(atLeast: .removed, reachability: .unreachable).count.shouldEqual(0)
    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Marking

    func test_mark_shouldOnlyProceedForwardInStatuses() {
        let member = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "4.4.4.4", port: 1001), nid: .random()), status: .joining)

        var membership: Cluster.Membership = [member]

        // marking no-member -> no-op

        let noChange = membership.mark(member.node, as: .joining)
        noChange.shouldBeNil() // already joining

        let change1 = membership.mark(member.node, as: .up)
        change1.shouldNotBeNil()

        // testing string output as well as field on purpose
        // as if the fromStatus is not set we may infer it from other places; but in such change, we definitely want it in the `from`
        change1?.fromStatus.shouldEqual(.joining)
        change1?.toStatus.shouldEqual(.up)
        "\(change1!)".shouldContain("fromStatus: joining, toStatus: up)")

        membership.mark(member.node, as: .joining).shouldBeNil() // can't move "back"
        membership.mark(member.node, as: .up).shouldBeNil() // don't move to "same"

        let change2 = membership.mark(member.node, as: .down)
        change2.shouldNotBeNil()
        change2?.fromStatus.shouldEqual(.up)
        change2?.toStatus.shouldEqual(.down)
        "\(change2!)".shouldContain("fromStatus: up, toStatus: down)")

        membership.mark(member.node, as: .joining).shouldBeNil() // can't move "back"
        membership.mark(member.node, as: .up).shouldBeNil() // can't move "back", from down
    }

    func test_mark_shouldNotReturnChangeForMarkingAsSameStatus() {
        let member = self.firstMember
        var membership: Cluster.Membership = [member]

        let noChange = membership.mark(member.node, as: member.status)
        noChange.shouldBeNil()
    }

    func test_mark_reachability() {
        let member = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "4.4.4.4", port: 1001), nid: .random()), status: .joining)

        var membership: Cluster.Membership = [member]
        membership.mark(member.node, reachability: .reachable).shouldEqual(nil) // no change

        let res1 = membership.mark(member.node, reachability: .unreachable)
        res1!.reachability.shouldEqual(.unreachable)

        membership.mark(member.node, reachability: .unreachable).shouldEqual(nil) // no change
        _ = membership.mark(member.node, reachability: .unreachable)
    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Replacements

    func test_join_overAnExistingMode_replacement() {
        var membership = self.initialMembership
        let secondReplacement = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "2.2.2.2", port: 8228), nid: .random()), status: .joining)
        let change = membership.join(secondReplacement.node)
        change.isReplacement.shouldBeTrue()
        let members = membership.members(secondReplacement.node.node)

        var secondDown = self.secondMember
        secondDown.status = .down
        members.shouldContain(secondDown)
        members.shouldContain(secondReplacement)
    }

    func test_mark_replacement() throws {
        var membership: Cluster.Membership = [self.firstMember]

        let firstReplacement = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "1.1.1.1", port: 7337), nid: .random()), status: .up)

        try shouldNotThrow {
            guard let change = membership.mark(firstReplacement.node, as: firstReplacement.status) else {
                throw TestError("Expected a change")
            }
            change.isReplacement.shouldBeTrue()
            change.replaced.shouldEqual(self.firstMember)
            change.fromStatus.shouldEqual(nil)
            change.node.shouldEqual(firstReplacement.node)
            change.toStatus.shouldEqual(.up)
        }
    }

    func test_replacement_changeCreation() {
        var existing = self.firstMember
        existing.status = .joining

        let replacement = Cluster.Member(node: UniqueNode(node: Node(systemName: "System", host: "1.1.1.1", port: 7337), nid: .random()), status: .up)

        let change = Cluster.MembershipChange(replaced: existing, by: replacement)
        change.isReplacement.shouldBeTrue()

        change.member.shouldEqual(replacement)
        change.node.shouldEqual(replacement.node)
        change.fromStatus.shouldBeNil() // the replacement is "from unknown" after all

        change.replaced!.status.shouldEqual(existing.status) // though we have the replaced member, it will have its own previous status
        change.replaced.shouldEqual(existing)

        change.isUp.shouldBeTrue() // up is the status of the replacement
    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Moving members along their lifecycle

    func test_moveForward_MemberStatus() {
        var member = self.firstMember
        member.status = .joining
        let joiningMember = member

        member.status = .up
        let upMember = member

        member.status = .leaving
        let leavingMember = member
        member.status = .down
        let downMember = member
        member.status = .removed

        member.status = .joining
        member.moveForward(.up).shouldEqual(Cluster.MembershipChange(member: joiningMember, toStatus: .up))
        member.status.shouldEqual(.up)
        member.moveForward(.joining).shouldEqual(nil) // no change, cannot move back

        member.moveForward(.up).shouldEqual(nil) // no change, cannot move to same status
        member.moveForward(.leaving).shouldEqual(Cluster.MembershipChange(member: upMember, toStatus: .leaving))
        member.status.shouldEqual(.leaving)

        member.moveForward(.joining).shouldEqual(nil) // no change, cannot move back
        member.moveForward(.up).shouldEqual(nil) // no change, cannot move back
        member.moveForward(.leaving).shouldEqual(nil) // no change, same
        member.moveForward(.down).shouldEqual(Cluster.MembershipChange(member: leavingMember, toStatus: .down))
        member.status.shouldEqual(.down)

        member.moveForward(.joining).shouldEqual(nil) // no change, cannot move back
        member.moveForward(.up).shouldEqual(nil) // no change, cannot move back
        member.moveForward(.leaving).shouldEqual(nil) // no change, cannot move back
        member.moveForward(.down).shouldEqual(nil) // no change, same
        member.moveForward(.removed).shouldEqual(Cluster.MembershipChange(member: downMember, toStatus: .removed))
        member.status.shouldEqual(.removed)

        member.status = .joining
        member.moveForward(.leaving).shouldEqual(Cluster.MembershipChange(member: joiningMember, toStatus: .leaving))
        member.status.shouldEqual(.leaving)

        member.status = .joining
        member.moveForward(.down).shouldEqual(Cluster.MembershipChange(member: joiningMember, toStatus: .down))
        member.status.shouldEqual(.down)

        member.status = .up
        member.moveForward(.removed).shouldEqual(Cluster.MembershipChange(member: upMember, toStatus: .removed))
        member.status.shouldEqual(.removed)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Diffing

    func test_membershipDiff_beEmpty_whenNothingChangedForIt() {
        let changed = self.initialMembership
        let diff = Cluster.Membership.diff(from: self.initialMembership, to: changed)
        diff.changes.count.shouldEqual(0)
    }

    func test_membershipDiff_shouldIncludeEntry_whenStatusChangedForIt() {
        let changed = self.initialMembership.marking(self.firstMember.node, as: .leaving)

        let diff = Cluster.Membership.diff(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry = diff.changes.first!
        diffEntry.node.shouldEqual(self.firstMember.node)
        diffEntry.fromStatus?.shouldEqual(.up)
        diffEntry.toStatus.shouldEqual(.leaving)
    }

    func test_membershipDiff_shouldIncludeEntry_whenMemberRemoved() {
        let changed = self.initialMembership.removingCompletely(self.firstMember.node)

        let diff = Cluster.Membership.diff(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry = diff.changes.first!
        diffEntry.node.shouldEqual(self.firstMember.node)
        diffEntry.fromStatus?.shouldEqual(.up)
        diffEntry.toStatus.shouldEqual(.removed)
    }

    func test_membershipDiff_shouldIncludeEntry_whenMemberAdded() {
        let changed = self.initialMembership.joining(self.newMember.node)

        let diff = Cluster.Membership.diff(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry = diff.changes.first!
        diffEntry.node.shouldEqual(self.newMember.node)
        diffEntry.fromStatus.shouldBeNil()
        diffEntry.toStatus.shouldEqual(.joining)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Merge Memberships

    func test_mergeForward_fromAhead_same() {
        var membership = self.initialMembership
        let ahead = self.initialMembership

        let changes = membership.mergeForward(fromAhead: ahead)

        changes.count.shouldEqual(0)
        membership.shouldEqual(self.initialMembership)
    }

    func test_mergeForward_fromAhead_membership_withAdditionalMember() {
        var membership = self.initialMembership
        var ahead = membership
        _ = ahead.join(self.newMember.node)

        let changes = membership.mergeForward(fromAhead: ahead)

        changes.count.shouldEqual(1)
        membership.shouldEqual(self.initialMembership.joining(self.newMember.node))
    }

    func test_mergeForward_fromAhead_membership_withMemberNowDown() {
        var membership = self.initialMembership
        var ahead = membership
        _ = ahead.mark(self.firstMember.node, as: .down)

        let changes = membership.mergeForward(fromAhead: ahead)

        changes.count.shouldEqual(1)
        membership.shouldEqual(self.initialMembership)
    }
}
