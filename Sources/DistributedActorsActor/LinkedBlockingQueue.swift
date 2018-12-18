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

import NIO
import NIOConcurrencyHelpers

public final class LinkedBlockingQueue<A> {
    public class Node<A> {
        var item: A?
        var next: Node<A>?

        public init(_ item: A?) {
            self.item = item
        }
    }

    private var producer: Node<A>
    private var consumer: Node<A>
    private let lock: Mutex = Mutex()
    private let notEmpty: Condition = Condition()
    private var count: Atomic<Int> = Atomic(value: 0)

    public init() {
        producer = Node(nil)
        consumer = producer
    }

    public func enqueue(_ item: A) -> Void {
        lock.synchronized {
            let next = Node(item)
            producer.next = next
            producer = next

            if count.add(1) == 0 {
                notEmpty.signal()
            }
        }
    }

    public func dequeue() -> A {
        return lock.synchronized { () -> A in
            while true {
                if let elem = take() {
                    return elem
                }
                notEmpty.wait(lock)
            }
        }
    }

    public func clear() {
        lock.synchronized {
            while let _ = take() {}
            self.count.store(0)
            notEmpty.signalAll()
        }
    }

    public func poll(_ timeout: TimeAmount) -> A? {
        return lock.synchronized { () -> A? in
            if let item = take() {
                return item
            }

            guard notEmpty.wait(lock, amount: timeout) else {
                return nil
            }

            return take()
        }
    }

    // Helper function to actually take an element out of the queue.
    // This function is not synchronized and expects the caller to
    // already hold the lock.
    private func take() -> A? {
        if count.load() > 0 {
            let newNext = consumer.next!
            let res = newNext.item!
            newNext.item = nil
            consumer.next = nil
            consumer = newNext
            if count.sub(1) > 1 {
                notEmpty.signal()
            }
            return res
        } else {
            return nil
        }
    }

    public func size() -> Int {
        return count.load()
    }
}
