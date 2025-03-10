# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2022 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------

from typing import List

from libc.stdint cimport uint64_t

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.model.c_enums.liquidity_side cimport LiquiditySide
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.c_enums.order_side cimport OrderSideParser
from nautilus_trader.model.c_enums.order_status cimport OrderStatus
from nautilus_trader.model.c_enums.order_status cimport OrderStatusParser
from nautilus_trader.model.c_enums.order_type cimport OrderType
from nautilus_trader.model.c_enums.order_type cimport OrderTypeParser
from nautilus_trader.model.c_enums.time_in_force cimport TimeInForceParser
from nautilus_trader.model.events.order cimport OrderAccepted
from nautilus_trader.model.events.order cimport OrderCanceled
from nautilus_trader.model.events.order cimport OrderCancelRejected
from nautilus_trader.model.events.order cimport OrderDenied
from nautilus_trader.model.events.order cimport OrderEvent
from nautilus_trader.model.events.order cimport OrderExpired
from nautilus_trader.model.events.order cimport OrderFilled
from nautilus_trader.model.events.order cimport OrderInitialized
from nautilus_trader.model.events.order cimport OrderModifyRejected
from nautilus_trader.model.events.order cimport OrderPendingCancel
from nautilus_trader.model.events.order cimport OrderPendingUpdate
from nautilus_trader.model.events.order cimport OrderRejected
from nautilus_trader.model.events.order cimport OrderSubmitted
from nautilus_trader.model.events.order cimport OrderTriggered
from nautilus_trader.model.events.order cimport OrderUpdated
from nautilus_trader.model.identifiers cimport TradeId
from nautilus_trader.model.objects cimport Quantity


# OrderStatus being used as trigger
cdef dict _ORDER_STATE_TABLE = {
    (OrderStatus.INITIALIZED, OrderStatus.DENIED): OrderStatus.DENIED,
    (OrderStatus.INITIALIZED, OrderStatus.SUBMITTED): OrderStatus.SUBMITTED,
    (OrderStatus.INITIALIZED, OrderStatus.ACCEPTED): OrderStatus.ACCEPTED,  # Covers external orders
    (OrderStatus.INITIALIZED, OrderStatus.REJECTED): OrderStatus.REJECTED,  # Covers external orders
    (OrderStatus.INITIALIZED, OrderStatus.CANCELED): OrderStatus.CANCELED,  # Covers external orders
    (OrderStatus.SUBMITTED, OrderStatus.REJECTED): OrderStatus.REJECTED,
    (OrderStatus.SUBMITTED, OrderStatus.CANCELED): OrderStatus.CANCELED,  # Covers FOK and IOC cases
    (OrderStatus.SUBMITTED, OrderStatus.ACCEPTED): OrderStatus.ACCEPTED,
    (OrderStatus.SUBMITTED, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.SUBMITTED, OrderStatus.FILLED): OrderStatus.FILLED,
    (OrderStatus.ACCEPTED, OrderStatus.REJECTED): OrderStatus.REJECTED,  # Covers StopLimit order
    (OrderStatus.ACCEPTED, OrderStatus.PENDING_UPDATE): OrderStatus.PENDING_UPDATE,
    (OrderStatus.ACCEPTED, OrderStatus.PENDING_CANCEL): OrderStatus.PENDING_CANCEL,
    (OrderStatus.ACCEPTED, OrderStatus.CANCELED): OrderStatus.CANCELED,
    (OrderStatus.ACCEPTED, OrderStatus.TRIGGERED): OrderStatus.TRIGGERED,
    (OrderStatus.ACCEPTED, OrderStatus.EXPIRED): OrderStatus.EXPIRED,
    (OrderStatus.ACCEPTED, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.ACCEPTED, OrderStatus.FILLED): OrderStatus.FILLED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.ACCEPTED): OrderStatus.ACCEPTED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.CANCELED): OrderStatus.CANCELED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.EXPIRED): OrderStatus.EXPIRED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.TRIGGERED): OrderStatus.TRIGGERED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.PENDING_UPDATE): OrderStatus.PENDING_UPDATE,  # Allow multiple requests
    (OrderStatus.PENDING_UPDATE, OrderStatus.PENDING_CANCEL): OrderStatus.PENDING_CANCEL,
    (OrderStatus.PENDING_UPDATE, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.PENDING_UPDATE, OrderStatus.FILLED): OrderStatus.FILLED,
    (OrderStatus.PENDING_CANCEL, OrderStatus.PENDING_CANCEL): OrderStatus.PENDING_CANCEL,  # Allow multiple requests
    (OrderStatus.PENDING_CANCEL, OrderStatus.CANCELED): OrderStatus.CANCELED,
    (OrderStatus.PENDING_CANCEL, OrderStatus.ACCEPTED): OrderStatus.ACCEPTED,  # Allows failed cancel requests
    (OrderStatus.PENDING_CANCEL, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.PENDING_CANCEL, OrderStatus.FILLED): OrderStatus.FILLED,
    (OrderStatus.TRIGGERED, OrderStatus.REJECTED): OrderStatus.REJECTED,
    (OrderStatus.TRIGGERED, OrderStatus.PENDING_UPDATE): OrderStatus.PENDING_UPDATE,
    (OrderStatus.TRIGGERED, OrderStatus.PENDING_CANCEL): OrderStatus.PENDING_CANCEL,
    (OrderStatus.TRIGGERED, OrderStatus.CANCELED): OrderStatus.CANCELED,
    (OrderStatus.TRIGGERED, OrderStatus.EXPIRED): OrderStatus.EXPIRED,
    (OrderStatus.TRIGGERED, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.TRIGGERED, OrderStatus.FILLED): OrderStatus.FILLED,
    (OrderStatus.PARTIALLY_FILLED, OrderStatus.PENDING_UPDATE): OrderStatus.PENDING_UPDATE,
    (OrderStatus.PARTIALLY_FILLED, OrderStatus.PENDING_CANCEL): OrderStatus.PENDING_CANCEL,
    (OrderStatus.PARTIALLY_FILLED, OrderStatus.CANCELED): OrderStatus.CANCELED,
    (OrderStatus.PARTIALLY_FILLED, OrderStatus.PARTIALLY_FILLED): OrderStatus.PARTIALLY_FILLED,
    (OrderStatus.PARTIALLY_FILLED, OrderStatus.FILLED): OrderStatus.FILLED,
}


cdef class Order:
    """
    The abstract base class for all orders.

    Parameters
    ----------
    init : OrderInitialized
        The order initialized event.

    Warnings
    --------
    This class should not be used directly, but through a concrete subclass.
    """

    def __init__(self, OrderInitialized init not None):
        Condition.positive(init.quantity, "init.quantity")

        self._events: List[OrderEvent] = [init]
        self._venue_order_ids: List[VenueOrderId] = []
        self._trade_ids: List[TradeId] = []
        self._fsm = FiniteStateMachine(
            state_transition_table=_ORDER_STATE_TABLE,
            initial_state=OrderStatus.INITIALIZED,
            trigger_parser=OrderStatusParser.to_str,
            state_parser=OrderStatusParser.to_str,
        )
        self._previous_status = OrderStatus.INITIALIZED

        # Identifiers
        self.trader_id = init.trader_id
        self.strategy_id = init.strategy_id
        self.instrument_id = init.instrument_id
        self.client_order_id = init.client_order_id
        self.order_list_id = init.order_list_id
        self.venue_order_id = None  # Can be None
        self.position_id = None  # Can be None
        self.account_id = None  # Can be None
        self.last_trade_id = None  # Can be None

        # Properties
        self.side = init.side
        self.type = init.type
        self.quantity = init.quantity
        self.time_in_force = init.time_in_force
        self.liquidity_side = LiquiditySide.NONE
        self.is_post_only = init.post_only
        self.is_reduce_only = init.reduce_only
        self.contingency_type = init.contingency_type
        self.linked_order_ids = init.linked_order_ids  # Can be None
        self.parent_order_id = init.parent_order_id  # Can be None
        self.tags = init.tags

        # Execution
        self.filled_qty = Quantity.zero_c(precision=0)
        self.leaves_qty = init.quantity
        self.avg_px = 0.0  # No fills yet
        self.slippage = 0.0

        # Timestamps
        self.init_id = init.id
        self.ts_init = init.ts_init
        self.ts_last = 0  # No fills yet

    def __eq__(self, Order other) -> bool:
        return self.client_order_id.value == other.client_order_id.value

    def __hash__(self) -> int:
        return hash(self.client_order_id.value)

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"{self.info()}, "
            f"status={self._fsm.state_string_c()}, "
            f"client_order_id={self.client_order_id.value}, "
            f"venue_order_id={self.venue_order_id}, "  # Can be None
            f"tags={self.tags})"
        )

    cpdef str info(self):
        """
        Return a summary description of the order.

        Returns
        -------
        str

        """
        raise NotImplementedError("method must be implemented in the subclass")  # pragma: no cover

    cpdef dict to_dict(self):
        """
        Return a dictionary representation of this object.

        Returns
        -------
        dict[str, object]

        """
        raise NotImplementedError("method must be implemented in the subclass")  # pragma: no cover

    cdef OrderStatus status_c(self) except *:
        return <OrderStatus>self._fsm.state

    cdef OrderInitialized init_event_c(self):
        return self._events[0]  # Guaranteed to contain the initialized event

    cdef OrderEvent last_event_c(self):
        return self._events[-1]  # Guaranteed to contain the initialized event

    cdef list events_c(self):
        return self._events.copy()

    cdef list venue_order_ids_c(self):
        return self._venue_order_ids.copy()

    cdef list trade_ids_c(self):
        return self._trade_ids.copy()

    cdef int event_count_c(self) except *:
        return len(self._events)

    cdef str status_string_c(self):
        return self._fsm.state_string_c()

    cdef str type_string_c(self):
        return OrderTypeParser.to_str(self.type)

    cdef str side_string_c(self):
        return OrderSideParser.to_str(self.side)

    cdef str tif_string_c(self):
        return TimeInForceParser.to_str(self.time_in_force)

    cdef bint has_price_c(self) except *:
        raise NotImplementedError("method must be implemented in subclass")  # pragma: no cover

    cdef bint has_trigger_price_c(self) except *:
        raise NotImplementedError("method must be implemented in subclass")  # pragma: no cover

    cdef bint is_buy_c(self) except *:
        return self.side == OrderSide.BUY

    cdef bint is_sell_c(self) except *:
        return self.side == OrderSide.SELL

    cdef bint is_passive_c(self) except *:
        return self.type != OrderType.MARKET

    cdef bint is_aggressive_c(self) except *:
        return self.type == OrderType.MARKET

    cdef bint is_contingency_c(self) except *:
        return self.contingency_type != ContingencyType.NONE

    cdef bint is_parent_order_c(self) except *:
        return self.contingency_type == ContingencyType.OTO

    cdef bint is_child_order_c(self) except *:
        return self.parent_order_id is not None

    cdef bint is_open_c(self) except *:
        return (
            self._fsm.state == OrderStatus.ACCEPTED
            or self._fsm.state == OrderStatus.TRIGGERED
            or self._fsm.state == OrderStatus.PENDING_CANCEL
            or self._fsm.state == OrderStatus.PENDING_UPDATE
            or self._fsm.state == OrderStatus.PARTIALLY_FILLED
        )

    cdef bint is_canceled_c(self) except *:
        return self._fsm.state == OrderStatus.CANCELED

    cdef bint is_closed_c(self) except *:
        return (
            self._fsm.state == OrderStatus.DENIED
            or self._fsm.state == OrderStatus.REJECTED
            or self._fsm.state == OrderStatus.CANCELED
            or self._fsm.state == OrderStatus.EXPIRED
            or self._fsm.state == OrderStatus.FILLED
        )

    cdef bint is_inflight_c(self) except *:
        return (
            self._fsm.state == OrderStatus.SUBMITTED
            or self._fsm.state == OrderStatus.PENDING_CANCEL
            or self._fsm.state == OrderStatus.PENDING_UPDATE
        )

    cdef bint is_pending_update_c(self) except *:
        return self._fsm.state == OrderStatus.PENDING_UPDATE

    cdef bint is_pending_cancel_c(self) except *:
        return self._fsm.state == OrderStatus.PENDING_CANCEL

    @property
    def symbol(self):
        """
        The orders ticker symbol.

        Returns
        -------
        Symbol

        """
        return self.instrument_id.symbol

    @property
    def venue(self):
        """
        The orders trading venue.

        Returns
        -------
        Venue

        """
        return self.instrument_id.venue

    @property
    def side_string(self) -> str:
        """
        The orders side as a string.

        Returns
        -------
        str

        """
        return self.side_string_c()

    @property
    def status(self):
        """
        The orders current status.

        Returns
        -------
        OrderStatus

        """
        return self.status_c()

    @property
    def init_event(self):
        """
        The initialization event for the order.

        Returns
        -------
        OrderInitialized

        """
        return self.init_event_c()

    @property
    def last_event(self):
        """
        The last event applied to the order.

        Returns
        -------
        OrderEvent

        """
        return self.last_event_c()

    @property
    def events(self):
        """
        The order events.

        Returns
        -------
        list[OrderEvent]

        """
        return self.events_c()

    @property
    def venue_order_ids(self):
        """
        The venue order IDs.

        Returns
        -------
        list[VenueOrderId]

        """
        return self.venue_order_ids_c().copy()

    @property
    def trade_ids(self):
        """
        The trade match IDs.

        Returns
        -------
        list[TradeId]

        """
        return self.trade_ids_c()

    @property
    def event_count(self):
        """
        The count of events applied to the order.

        Returns
        -------
        int

        """
        return self.event_count_c()

    @property
    def has_price(self):
        """
        If the order has a `price` property.

        Returns
        -------
        bool

        """
        return self.has_price_c()

    @property
    def has_trigger_price(self):
        """
        If the order has a `trigger_price` property.

        Returns
        -------
        bool

        """
        return self.has_trigger_price_c()

    @property
    def is_buy(self):
        """
        If the order side is ``BUY``.

        Returns
        -------
        bool

        """
        return self.is_buy_c()

    @property
    def is_sell(self):
        """
        If the order side is ``SELL``.

        Returns
        -------
        bool

        """
        return self.is_sell_c()

    @property
    def is_passive(self):
        """
        If the order is passive (`order.type` **not** ``MARKET``).

        Returns
        -------
        bool

        """
        return self.is_passive_c()

    @property
    def is_aggressive(self):
        """
        If the order is aggressive (`order.type` is ``MARKET``).

        Returns
        -------
        bool

        """
        return self.is_aggressive_c()

    @property
    def is_contingency(self):
        """
        If the order has a contingency (`order.contingency_type` is not ``NONE``).

        Returns
        -------
        bool

        """
        return self.is_contingency_c()

    @property
    def is_parent_order(self):
        """
        If the order has **at least** one child order.

        Returns
        -------
        bool

        """
        return self.is_parent_order_c()

    @property
    def is_child_order(self):
        """
        If the order has a parent order.

        Returns
        -------
        bool

        """
        return self.is_child_order_c()

    @property
    def is_inflight(self):
        """
        If the order is in-flight (order request sent to the trading venue).

        An order is considered in-flight when its status is any of;

        - ``SUBMITTED``
        - ``PENDING_CANCEL``
        - ``PENDING_UPDATE``

        Returns
        -------
        bool

        """
        return self.is_inflight_c()

    @property
    def is_open(self):
        """
        If the order is open at the trading venue.

        An order is considered open when its status is any of;

        - ``ACCEPTED``
        - ``TRIGGERED``
        - ``PENDING_CANCEL``
        - ``PENDING_UPDATE``
        - ``PARTIALLY_FILLED``

        Returns
        -------
        bool

        """
        return self.is_open_c()

    @property
    def is_canceled(self):
        """
        If current `order.status` is ``CANCELED``.

        Returns
        -------
        bool

        """
        return self.is_canceled_c()

    @property
    def is_closed(self):
        """
        If the order is closed.

        An order is considered closed when its state can no longer change.
        The possible states of closed orders include;

        - ``DENIED``
        - ``REJECTED``
        - ``CANCELED``
        - ``EXPIRED``
        - ``FILLED``

        Returns
        -------
        bool

        """
        return self.is_closed_c()

    @property
    def is_pending_update(self):
        """
        If current `order.status` is ``PENDING_UPDATE``.

        Returns
        -------
        bool

        """
        return self.is_pending_update_c()

    @property
    def is_pending_cancel(self):
        """
        If current `order.status` is ``PENDING_CANCEL``.

        Returns
        -------
        bool

        """
        return self.is_pending_cancel_c()

    @staticmethod
    cdef OrderSide opposite_side_c(OrderSide side) except *:
        if side == OrderSide.BUY:
            return OrderSide.SELL
        elif side == OrderSide.SELL:
            return OrderSide.BUY
        else:  # pragma: no cover (design-time error)
            raise ValueError(f"invalid OrderSide, was {side}")

    @staticmethod
    cdef OrderSide closing_side_c(PositionSide side) except *:
        if side == PositionSide.LONG:
            return OrderSide.SELL
        elif side == PositionSide.SHORT:
            return OrderSide.BUY
        else:  # pragma: no cover (design-time error)
            raise ValueError(f"invalid OrderSide, was {side}")

    @staticmethod
    def opposite_side(OrderSide side) -> OrderSide:
        """
        Return the opposite order side from the given side.

        Parameters
        ----------
        side : OrderSide {``BUY``, ``SELL``}
            The original order side.

        Returns
        -------
        OrderSide

        Raises
        ------
        ValueError
            If `side` is invalid.

        """
        return Order.opposite_side_c(side)

    @staticmethod
    def closing_side(PositionSide side) -> OrderSide:
        """
        Return the order side needed to close a position with the given side.

        Parameters
        ----------
        side : PositionSide {``LONG``, ``SHORT``}
            The side of the position to close.

        Returns
        -------
        OrderSide

        Raises
        ------
        ValueError
            If `side` is ``FLAT`` or invalid.

        """
        return Order.closing_side_c(side)

    cpdef void apply(self, OrderEvent event) except *:
        """
        Apply the given order event to the order.

        Parameters
        ----------
        event : OrderEvent
            The order event to apply.

        Raises
        ------
        ValueError
            If `self.client_order_id` is not equal to `event.client_order_id`.
        ValueError
            If `self.venue_order_id` and `event.venue_order_id` are both not ``None``, and are not equal.
        InvalidStateTrigger
            If `event` is not a valid trigger from the current `order.status`.
        KeyError
            If `event` is `OrderFilled` and `event.trade_id` already applied to the order.

        """
        Condition.not_none(event, "event")
        Condition.equal(event.client_order_id, self.client_order_id, "event.client_order_id", "self.client_order_id")
        if self.venue_order_id is not None and event.venue_order_id is not None and not isinstance(event, OrderUpdated):
            Condition.equal(self.venue_order_id, event.venue_order_id, "self.venue_order_id", "event.venue_order_id")

        # Handle event (FSM can raise InvalidStateTrigger)
        if isinstance(event, OrderDenied):
            self._fsm.trigger(OrderStatus.DENIED)
            self._denied(event)
        elif isinstance(event, OrderSubmitted):
            self._fsm.trigger(OrderStatus.SUBMITTED)
            self._submitted(event)
        elif isinstance(event, OrderRejected):
            self._fsm.trigger(OrderStatus.REJECTED)
            self._rejected(event)
        elif isinstance(event, OrderAccepted):
            self._fsm.trigger(OrderStatus.ACCEPTED)
            self._accepted(event)
        elif isinstance(event, OrderPendingUpdate):
            self._previous_status = <OrderStatus>self._fsm.state
            self._fsm.trigger(OrderStatus.PENDING_UPDATE)
        elif isinstance(event, OrderPendingCancel):
            self._previous_status = <OrderStatus>self._fsm.state
            self._fsm.trigger(OrderStatus.PENDING_CANCEL)
        elif isinstance(event, OrderModifyRejected):
            if self._fsm.state == OrderStatus.PENDING_UPDATE:
                self._fsm.trigger(self._previous_status)
        elif isinstance(event, OrderCancelRejected):
            if self._fsm.state == OrderStatus.PENDING_CANCEL:
                self._fsm.trigger(self._previous_status)
        elif isinstance(event, OrderUpdated):
            if self._fsm.state == OrderStatus.PENDING_UPDATE:
                self._fsm.trigger(self._previous_status)
            self._updated(event)
        elif isinstance(event, OrderTriggered):
            Condition.true(self.type == OrderType.STOP_LIMIT, "can only trigger a STOP_LIMIT order")
            self._fsm.trigger(OrderStatus.TRIGGERED)
            self._triggered(event)
        elif isinstance(event, OrderCanceled):
            self._fsm.trigger(OrderStatus.CANCELED)
            self._canceled(event)
        elif isinstance(event, OrderExpired):
            self._fsm.trigger(OrderStatus.EXPIRED)
            self._expired(event)
        elif isinstance(event, OrderFilled):
            # Check identifiers
            if self.venue_order_id is None:
                self.venue_order_id = event.venue_order_id
            else:
                Condition.not_in(event.trade_id, self._trade_ids, "event.trade_id", "_trade_ids")
            # Fill order
            self._filled(event)
        else:  # pragma: no cover (design-time error)
            raise ValueError(f"invalid OrderEvent, was {type(event)}")

        # Update events last as FSM may raise InvalidStateTrigger
        self._events.append(event)

    cdef void _denied(self, OrderDenied event) except *:
        pass  # Do nothing else

    cdef void _submitted(self, OrderSubmitted event) except *:
        self.account_id = event.account_id

    cdef void _rejected(self, OrderRejected event) except *:
        pass  # Do nothing else

    cdef void _accepted(self, OrderAccepted event) except *:
        self.venue_order_id = event.venue_order_id

    cdef void _updated(self, OrderUpdated event) except *:
        if event.quantity is None:
            return

        cdef uint64_t raw_leaves_qty = self.leaves_qty.raw_uint64_c() - self.filled_qty.raw_uint64_c()
        self.leaves_qty = Quantity.from_raw_c(raw_leaves_qty, self.quantity._mem.precision)
        self.quantity = event.quantity

    cdef void _triggered(self, OrderTriggered event) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")  # pragma: no cover

    cdef void _canceled(self, OrderCanceled event) except *:
        pass  # Do nothing else

    cdef void _expired(self, OrderExpired event) except *:
        pass  # Do nothing else

    cdef void _filled(self, OrderFilled fill) except *:
        if self.filled_qty._mem.raw + fill.last_qty._mem.raw < self.quantity._mem.raw:
            self._fsm.trigger(OrderStatus.PARTIALLY_FILLED)
        else:
            self._fsm.trigger(OrderStatus.FILLED)

        self.venue_order_id = fill.venue_order_id
        self.position_id = fill.position_id
        self.strategy_id = fill.strategy_id
        self._trade_ids.append(fill.trade_id)
        self.last_trade_id = fill.trade_id
        cdef uint64_t raw_filled_qty = self.filled_qty._mem.raw + fill.last_qty._mem.raw
        cdef int64_t raw_leaves_qty = self.quantity._mem.raw - raw_filled_qty
        if raw_leaves_qty < 0:
            raise ValueError(
                f"invalid order.leaves_qty: was {<uint64_t>raw_leaves_qty / 1e9}, "
                f"order.quantity={self.quantity}, "
                f"order.filled_qty={self.filled_qty}, "
                f"fill.last_qty={fill.last_qty}, "
                f"fill={fill}",
            )
        self.filled_qty.add_assign(fill.last_qty)
        self.leaves_qty = Quantity.from_raw_c(<uint64_t>raw_leaves_qty, fill.last_qty.precision)
        self.ts_last = fill.ts_event
        self.avg_px = self._calculate_avg_px(fill.last_qty.as_f64_c(), fill.last_px.as_f64_c())
        self.liquidity_side = fill.liquidity_side
        self._set_slippage()

    cdef double _calculate_avg_px(self, double last_qty, double last_px):
        if self.avg_px == 0.0:
            return last_px

        cdef double filled_qty_f64 = self.filled_qty.as_f64_c()
        cdef double total_qty = filled_qty_f64 + last_qty
        if total_qty > 0:  # Protect divide by zero
            return ((self.avg_px * filled_qty_f64) + (last_px * last_qty)) / total_qty

    cdef void _set_slippage(self) except *:
        pass  # Optionally implement
