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

from decimal import Decimal
from typing import Optional
from cpython.datetime cimport datetime
from libc.stdint cimport int64_t

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.message cimport Document
from nautilus_trader.core.uuid cimport UUID4
from nautilus_trader.model.c_enums.contingency_type cimport ContingencyTypeParser
from nautilus_trader.model.c_enums.liquidity_side cimport LiquiditySide
from nautilus_trader.model.c_enums.liquidity_side cimport LiquiditySideParser
from nautilus_trader.model.c_enums.order_side cimport OrderSideParser
from nautilus_trader.model.c_enums.order_status cimport OrderStatus
from nautilus_trader.model.c_enums.order_status cimport OrderStatusParser
from nautilus_trader.model.c_enums.order_type cimport OrderTypeParser
from nautilus_trader.model.c_enums.position_side cimport PositionSide
from nautilus_trader.model.c_enums.position_side cimport PositionSideParser
from nautilus_trader.model.c_enums.time_in_force cimport TimeInForceParser
from nautilus_trader.model.c_enums.trailing_offset_type cimport TrailingOffsetType
from nautilus_trader.model.c_enums.trailing_offset_type cimport TrailingOffsetTypeParser
from nautilus_trader.model.c_enums.trigger_type cimport TriggerType
from nautilus_trader.model.c_enums.trigger_type cimport TriggerTypeParser
from nautilus_trader.model.identifiers cimport AccountId
from nautilus_trader.model.identifiers cimport ClientOrderId
from nautilus_trader.model.identifiers cimport InstrumentId
from nautilus_trader.model.identifiers cimport TradeId
from nautilus_trader.model.identifiers cimport Venue
from nautilus_trader.model.identifiers cimport VenueOrderId
from nautilus_trader.model.objects cimport Quantity


cdef class ExecutionReport(Document):
    """
    The abstract base class for all execution reports.
    """

    def __init__(
        self,
        AccountId account_id not None,
        InstrumentId instrument_id not None,
        UUID4 report_id not None,
        int64_t ts_init,
    ):
        super().__init__(
            report_id,
            ts_init,
        )
        self.account_id = account_id
        self.instrument_id = instrument_id


cdef class OrderStatusReport(ExecutionReport):
    """
    Represents an order status at a point in time.

    Parameters
    ----------
    account_id : AccountId
        The account ID for the report.
    instrument_id : InstrumentId
        The instrument ID for the report.
    venue_order_id : VenueOrderId
        The reported order ID (assigned by the venue).
    order_side : OrderSide {``BUY``, ``SELL``}
        The reported order side.
    order_type : OrderType
        The reported order type.
    time_in_force : TimeInForce {``GTC``, ``IOC``, ``FOK``, ``GTD``, ``DAY``, ``AT_THE_OPEN``, ``AT_THE_CLOSE``}
        The reported order time in force.
    order_status : OrderStatus
        The reported order status at the exchange.
    quantity : Quantity
        The reported order original quantity.
    filled_qty : Quantity
        The reported filled quantity at the exchange.
    report_id : UUID4
        The report ID.
    ts_accepted : int64
        The UNIX timestamp (nanoseconds) when the reported order was accepted.
    ts_last : int64
        The UNIX timestamp (nanoseconds) of the last order status change.
    ts_init : int64
        The UNIX timestamp (nanoseconds) when the object was initialized.
    client_order_id : ClientOrderId, optional
        The reported client order ID.
    order_list_id : OrderListId, optional
        The reported order list ID associated with the order.
    contingency_type : ContingencyType, default ``NONE``
        The reported order contingency type.
    expire_time : datetime, optional
        The order expiration.
    price : Price, optional
        The reported order price (LIMIT).
    trigger_price : Price, optional
        The reported order trigger price (STOP).
    trigger_type : TriggerType, default ``NONE``
        The reported order trigger type.
    limit_offset : Decimal, optional
        The trailing offset for the order price (LIMIT).
    trailing_offset : Decimal, optional
        The trailing offset for the trigger price (STOP).
    offset_type : TrailingOffsetType, default ``NONE``
        The order trailing offset type.
    avg_px : Decimal, optional
        The reported order average fill price.
    display_qty : Quantity, optional
        The reported order quantity displayed on the public book (iceberg).
    post_only : bool, default False
        If the reported order will only provide liquidity (make a market).
    reduce_only : bool, default False
        If the reported order carries the 'reduce-only' execution instruction.
    cancel_reason : str, optional
        The reported reason for order cancellation.
    ts_triggered : int64, optional
        The UNIX timestamp (nanoseconds) when the object was initialized.

    Raises
    ------
    ValueError
        If `quantity` is not positive (> 0).
    ValueError
        If `filled_qty` is negative (< 0).
    ValueError
        If `trigger_price` is not ``None`` and `trigger_price` is equal to ``TriggerType.NONE``.
    ValueError
        If `limit_offset` or `trailing_offset` is not ``None`` and offset_type is equal to ``TrailingOffsetType.NONE``.
    """

    def __init__(
        self,
        AccountId account_id not None,
        InstrumentId instrument_id not None,
        VenueOrderId venue_order_id not None,
        OrderSide order_side,
        OrderType order_type,
        TimeInForce time_in_force,
        OrderStatus order_status,
        Quantity quantity not None,
        Quantity filled_qty not None,
        UUID4 report_id not None,
        int64_t ts_accepted,
        int64_t ts_last,
        int64_t ts_init,
        ClientOrderId client_order_id = None,  # Can be None (external order)
        OrderListId order_list_id = None,  # Can be None
        ContingencyType contingency_type = ContingencyType.NONE,
        datetime expire_time = None,  # Can be None
        Price price = None,  # Can be None
        Price trigger_price = None,  # Can be None
        TriggerType trigger_type = TriggerType.NONE,
        limit_offset: Optional[Decimal] = None,  # Can be None
        trailing_offset: Optional[Decimal] = None,  # Can be None
        TrailingOffsetType offset_type = TrailingOffsetType.NONE,
        avg_px: Optional[Decimal] = None,  # Can be None
        Quantity display_qty = None,  # Can be None
        bint post_only = False,
        bint reduce_only = False,
        str cancel_reason = None,  # Can be None
        ts_triggered: Optional[int] = None,  # Can be None
    ):
        Condition.positive(quantity, "quantity")
        Condition.not_negative(filled_qty, "filled_qty")
        if trigger_price is not None:
            Condition.not_equal(trigger_type, TriggerType.NONE, "trigger_type", "NONE")
        if limit_offset is not None or trailing_offset is not None:
            Condition.not_equal(offset_type, TrailingOffsetType.NONE, "offset_type", "NONE")

        super().__init__(
            account_id,
            instrument_id,
            report_id,
            ts_init,
        )
        self.client_order_id = client_order_id
        self.order_list_id = order_list_id
        self.venue_order_id = venue_order_id
        self.order_side = order_side
        self.order_type = order_type
        self.contingency_type = contingency_type
        self.time_in_force = time_in_force
        self.expire_time = expire_time
        self.order_status = order_status
        self.price = price
        self.trigger_price = trigger_price
        self.trigger_type = trigger_type
        self.limit_offset = limit_offset
        self.trailing_offset = trailing_offset
        self.offset_type = offset_type
        self.quantity = quantity
        self.filled_qty = filled_qty
        self.leaves_qty = Quantity(self.quantity.as_f64_c() - self.filled_qty.as_f64_c(), self.quantity._mem.precision)
        self.display_qty = display_qty
        self.avg_px = avg_px
        self.post_only = post_only
        self.reduce_only = reduce_only
        self.cancel_reason = cancel_reason
        self.ts_accepted = ts_accepted
        self.ts_triggered = ts_triggered or 0
        self.ts_last = ts_last

    def __eq__(self, OrderStatusReport other) -> bool:
        return (
            self.account_id == other.account_id
            and self.instrument_id == other.instrument_id
            and self.venue_order_id == other.venue_order_id
            and self.ts_accepted == other.ts_accepted
        )

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"account_id={self.account_id}, "
            f"instrument_id={self.instrument_id.value}, "
            f"client_order_id={self.client_order_id}, "
            f"order_list_id={self.order_list_id}, "
            f"venue_order_id={self.venue_order_id.value}, "
            f"order_side={OrderSideParser.to_str(self.order_side)}, "
            f"order_type={OrderTypeParser.to_str(self.order_type)}, "
            f"contingency_type={ContingencyTypeParser.to_str(self.contingency_type)}, "
            f"time_in_force={TimeInForceParser.to_str(self.time_in_force)}, "
            f"expire_time={self.expire_time}, "
            f"order_status={OrderStatusParser.to_str(self.order_status)}, "
            f"price={self.price}, "
            f"trigger_price={self.trigger_price}, "
            f"trigger_type={TriggerTypeParser.to_str(self.trigger_type)}, "
            f"limit_offset={self.limit_offset}, "
            f"trailing_offset={self.trailing_offset}, "
            f"offset_type={TrailingOffsetTypeParser.to_str(self.offset_type)}, "
            f"quantity={self.quantity.to_str()}, "
            f"filled_qty={self.filled_qty.to_str()}, "
            f"leaves_qty={self.leaves_qty.to_str()}, "
            f"display_qty={self.display_qty.to_str() if self.display_qty is not None else None}, "
            f"avg_px={self.avg_px}, "
            f"post_only={self.post_only}, "
            f"reduce_only={self.reduce_only}, "
            f"cancel_reason={self.cancel_reason}, "
            f"report_id={self.id}, "
            f"ts_accepted={self.ts_accepted}, "
            f"ts_triggered={self.ts_triggered}, "
            f"ts_last={self.ts_last}, "
            f"ts_init={self.ts_init})"
        )


cdef class TradeReport(ExecutionReport):
    """
    Represents a report of a single trade.

    Parameters
    ----------
    account_id : AccountId
        The account ID for the report.
    instrument_id : InstrumentId
        The reported instrument ID for the trade.
    client_order_id : ClientOrderId, optional
        The reported client order ID for the trade.
    venue_order_id : VenueOrderId
        The reported venue order ID (assigned by the venue) for the trade.
    venue_position_id : PositionId, optional
        The reported venue position ID for the trade. If the trading venue has
        assigned a position ID / ticket for the trade then pass that here,
        otherwise pass ``None`` and the execution engine OMS will handle
        position ID resolution.
    trade_id : TradeId
        The reported trade match ID (assigned by the venue).
    order_side : OrderSide {``BUY``, ``SELL``}
        The reported order side for the trade.
    last_qty : Quantity
        The reported quantity of the trade.
    last_px : Price
        The reported price of the trade.
    commission : Money, optional
        The reported commission for the trade (can be ``None``).
    liquidity_side : LiquiditySide {``NONE``, ``MAKER``, ``TAKER``}
        The reported liquidity side for the trade.
    report_id : UUID4
        The report ID.
    ts_event : int64
        The UNIX timestamp (nanoseconds) when the trade occurred.
    ts_init : int64
        The UNIX timestamp (nanoseconds) when the object was initialized.

    Raises
    ------
    ValueError
        If `last_qty` is not positive (> 0).
    """

    def __init__(
        self,
        AccountId account_id not None,
        InstrumentId instrument_id not None,
        VenueOrderId venue_order_id not None,
        TradeId trade_id not None,
        OrderSide order_side,
        Quantity last_qty not None,
        Price last_px not None,
        LiquiditySide liquidity_side,
        UUID4 report_id not None,
        int64_t ts_event,
        int64_t ts_init,
        ClientOrderId client_order_id = None,  # Can be None (external order)
        PositionId venue_position_id = None,  # Can be None
        Money commission = None,  # Can be None
    ):
        Condition.positive(last_qty, "last_qty")

        super().__init__(
            account_id,
            instrument_id,
            report_id,
            ts_init,
        )
        self.client_order_id = client_order_id
        self.venue_order_id = venue_order_id
        self.venue_position_id = venue_position_id
        self.trade_id = trade_id
        self.order_side = order_side
        self.last_qty = last_qty
        self.last_px = last_px
        self.commission = commission
        self.liquidity_side = liquidity_side
        self.ts_event = ts_event

    def __eq__(self, TradeReport other) -> bool:
        return (
            self.account_id == other.account_id
            and self.instrument_id == other.instrument_id
            and self.venue_order_id == other.venue_order_id
            and self.trade_id == other.trade_id
            and self.ts_event == other.ts_event
        )

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"account_id={self.account_id}, "
            f"instrument_id={self.instrument_id.value}, "
            f"client_order_id={self.client_order_id}, "
            f"venue_order_id={self.venue_order_id.value}, "
            f"venue_position_id={self.venue_position_id}, "
            f"trade_id={self.trade_id.value}, "
            f"order_side={OrderSideParser.to_str(self.order_side)}, "
            f"last_qty={self.last_qty.to_str()}, "
            f"last_px={self.last_px}, "
            f"commission={self.commission.to_str()}, "
            f"liquidity_side={LiquiditySideParser.to_str(self.liquidity_side)}, "
            f"report_id={self.id}, "
            f"ts_event={self.ts_event}, "
            f"ts_init={self.ts_init})"
        )


cdef class PositionStatusReport(ExecutionReport):
    """
    Represents a position status at a point in time.

    Parameters
    ----------
    account_id : AccountId
        The account ID for the report.
    instrument_id : InstrumentId
        The reported instrument ID for the position.
    position_side : PositionSide {``FLAT``, ``LONG``, ``SHORT``}
        The reported position side at the exchange.
    quantity : Quantity
        The reported position quantity at the exchange.
    report_id : UUID4
        The report ID.
    ts_last : int64
        The UNIX timestamp (nanoseconds) of the last position change.
    ts_init : int64
        The UNIX timestamp (nanoseconds) when the object was initialized.
    venue_position_id : PositionId, optional
        The reported venue position ID (assigned by the venue). If the trading
        venue has assigned a position ID / ticket for the trade then pass that
        here, otherwise pass ``None`` and the execution engine OMS will handle
        position ID resolution.
    """

    def __init__(
        self,
        AccountId account_id not None,
        InstrumentId instrument_id not None,
        PositionSide position_side,
        Quantity quantity not None,
        UUID4 report_id not None,
        int64_t ts_last,
        int64_t ts_init,
        PositionId venue_position_id = None,  # Can be None
    ):
        super().__init__(
            account_id,
            instrument_id,
            report_id,
            ts_init,
        )
        self.venue_position_id = venue_position_id
        self.position_side = position_side
        self.quantity = quantity
        self.net_qty = -self.quantity.as_f64_c() if quantity._mem.raw < 0 else self.quantity.as_f64_c()
        self.ts_last = ts_last

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"account_id={self.account_id}, "
            f"instrument_id={self.instrument_id.value}, "
            f"venue_position_id={self.venue_position_id}, "
            f"position_side={PositionSideParser.to_str(self.position_side)}, "
            f"quantity={self.quantity.to_str()}, "
            f"net_qty={self.net_qty}, "
            f"report_id={self.id}, "
            f"ts_last={self.ts_last}, "
            f"ts_init={self.ts_init})"
        )


cdef class ExecutionMassStatus(Document):
    """
    Represents an execution mass status report for an execution client -
    including status of all orders, trades for those orders and open positions.

    Parameters
    ----------
    venue : Venue
        The venue for the report.
    client_id : ClientId
        The client ID for the report.
    account_id : AccountId
        The account ID for the report.
    report_id : UUID4
        The report ID.
    ts_init : int64
        The UNIX timestamp (nanoseconds) when the object was initialized.
    """

    def __init__(
        self,
        ClientId client_id not None,
        AccountId account_id not None,
        Venue venue not None,
        UUID4 report_id not None,
        int64_t ts_init,
    ):
        super().__init__(
            report_id,
            ts_init,
        )
        self.client_id = client_id
        self.account_id = account_id
        self.venue = venue

        self._order_reports = {}     # type: dict[VenueOrderId, OrderStatusReport]
        self._trade_reports = {}     # type: dict[VenueOrderId, list[TradeReport]]
        self._position_reports = {}  # type: dict[InstrumentId, list[PositionStatusReport]]

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"client_id={self.client_id}, "
            f"account_id={self.account_id.value}, "
            f"venue={self.venue.value}, "
            f"order_reports={self._order_reports}, "
            f"trade_reports={self._trade_reports}, "
            f"position_reports={self._position_reports}, "
            f"report_id={self.id}, "
            f"ts_init={self.ts_init})"
        )

    cpdef dict order_reports(self):
        """
        Return the order status reports.

        Returns
        -------
        dict[VenueOrderId, OrderStatusReport]

        """
        return self._order_reports.copy()

    cpdef dict trade_reports(self):
        """
        Return the trade reports.

        Returns
        -------
        dict[VenueOrderId, list[TradeReport]

        """
        return self._trade_reports.copy()

    cpdef dict position_reports(self):
        """
        Return the position status reports.

        Returns
        -------
        dict[InstrumentId, list[PositionStatusReport]]

        """
        return self._position_reports.copy()

    cpdef void add_order_reports(self, list reports) except *:
        """
        Add the order reports to the mass status.

        Parameters
        ----------
        reports : list[OrderStatusReport]
            The list of reports to add.

        Raises
        -------
        TypeError
            If `reports` contains a type other than `TradeReport`.

        """
        Condition.not_none(reports, "reports")

        cdef OrderStatusReport report
        for report in reports:
            self._order_reports[report.venue_order_id] = report

    cpdef void add_trade_reports(self, list reports) except *:
        """
        Add the trade reports to the mass status.

        Parameters
        ----------
        reports : list[TradeReport]
            The list of reports to add.

        Raises
        -------
        TypeError
            If `reports` contains a type other than `TradeReport`.

        """
        Condition.not_none(reports, "reports")

        # Sort reports by venue order ID
        cdef TradeReport report
        for report in reports:
            if report.venue_order_id not in self._trade_reports:
                self._trade_reports[report.venue_order_id] = []
            self._trade_reports[report.venue_order_id].append(report)

    cpdef void add_position_reports(self, list reports) except *:
        """
        Add the position status reports to the mass status.

        Parameters
        ----------
        reports : list[PositionStatusReport]
            The reports to add.

        """
        Condition.not_none(reports, "reports")

        # Sort reports by instrument ID
        for report in reports:
            if report.instrument_id not in self._position_reports:
                self._position_reports[report.instrument_id] = []
            self._position_reports[report.instrument_id].append(report)
