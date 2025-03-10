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

from libc.stdint cimport int64_t

from nautilus_trader.accounting.accounts.base cimport Account
from nautilus_trader.backtest.execution_client cimport BacktestExecClient
from nautilus_trader.backtest.models cimport FillModel
from nautilus_trader.backtest.models cimport LatencyModel
from nautilus_trader.cache.cache cimport Cache
from nautilus_trader.common.clock cimport Clock
from nautilus_trader.common.logging cimport LoggerAdapter
from nautilus_trader.common.queue cimport Queue
from nautilus_trader.common.uuid cimport UUIDFactory
from nautilus_trader.execution.messages cimport TradingCommand
from nautilus_trader.model.c_enums.account_type cimport AccountType
from nautilus_trader.model.c_enums.book_type cimport BookType
from nautilus_trader.model.c_enums.liquidity_side cimport LiquiditySide
from nautilus_trader.model.c_enums.oms_type cimport OMSType
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.currency cimport Currency
from nautilus_trader.model.data.bar cimport Bar
from nautilus_trader.model.data.tick cimport QuoteTick
from nautilus_trader.model.data.tick cimport TradeTick
from nautilus_trader.model.identifiers cimport ClientOrderId
from nautilus_trader.model.identifiers cimport InstrumentId
from nautilus_trader.model.identifiers cimport PositionId
from nautilus_trader.model.identifiers cimport StrategyId
from nautilus_trader.model.identifiers cimport TradeId
from nautilus_trader.model.identifiers cimport Venue
from nautilus_trader.model.identifiers cimport VenueOrderId
from nautilus_trader.model.instruments.base cimport Instrument
from nautilus_trader.model.objects cimport Money
from nautilus_trader.model.objects cimport Price
from nautilus_trader.model.objects cimport Quantity
from nautilus_trader.model.orderbook.book cimport OrderBook
from nautilus_trader.model.orderbook.data cimport OrderBookData
from nautilus_trader.model.orders.base cimport Order
from nautilus_trader.model.orders.limit cimport LimitOrder
from nautilus_trader.model.orders.market cimport MarketOrder
from nautilus_trader.model.position cimport Position


cdef class SimulatedExchange:
    cdef Clock _clock
    cdef UUIDFactory _uuid_factory
    cdef LoggerAdapter _log

    cdef readonly Venue id
    """The exchange ID.\n\n:returns: `Venue`"""
    cdef readonly OMSType oms_type
    """The exchange order management system type.\n\n:returns: `OMSType`"""
    cdef readonly BookType book_type
    """The exchange default order book type.\n\n:returns: `BookType`"""
    cdef readonly Cache cache
    """The cache wired to the exchange.\n\n:returns: `CacheFacade`"""
    cdef readonly BacktestExecClient exec_client
    """The execution client wired to the exchange.\n\n:returns: `BacktestExecClient`"""

    cdef readonly AccountType account_type
    """The account base currency.\n\n:returns: `AccountType`"""
    cdef readonly Currency base_currency
    """The account base currency (None for multi-currency accounts).\n\n:returns: `Currency` or ``None``"""
    cdef readonly list starting_balances
    """The account starting balances for each backtest run.\n\n:returns: `bool`"""
    cdef readonly default_leverage
    """The accounts default leverage.\n\n:returns: `Decimal`"""
    cdef readonly dict leverages
    """The accounts instrument specific leverage configuration.\n\n:returns: `dict[InstrumentId, Decimal]`"""
    cdef readonly bint is_frozen_account
    """If the account for the exchange is frozen.\n\n:returns: `bool`"""
    cdef readonly LatencyModel latency_model
    """The latency model for the exchange.\n\n:returns: `LatencyModel`"""
    cdef readonly FillModel fill_model
    """The fill model for the exchange.\n\n:returns: `FillModel`"""
    cdef readonly bint reject_stop_orders
    """If stop orders are rejected on submission if in the market.\n\n:returns: `bool`"""
    cdef readonly list modules
    """The simulation modules registered with the exchange.\n\n:returns: `list[SimulationModule]`"""
    cdef readonly dict instruments
    """The exchange instruments.\n\n:returns: `dict[InstrumentId, Instrument]`"""

    cdef dict _instrument_indexer

    cdef dict _books
    cdef dict _last
    cdef dict _last_bids
    cdef dict _last_asks
    cdef dict _last_bid_bars
    cdef dict _last_ask_bars
    cdef dict _order_index
    cdef dict _orders_bid
    cdef dict _orders_ask
    cdef dict _oto_orders
    cdef bint _bar_execution

    cdef dict _symbol_pos_count
    cdef dict _symbol_ord_count
    cdef int _executions_count
    cdef Queue _message_queue
    cdef list _inflight_queue
    cdef dict _inflight_counter

    cpdef Price best_bid_price(self, InstrumentId instrument_id)
    cpdef Price best_ask_price(self, InstrumentId instrument_id)
    cpdef OrderBook get_book(self, InstrumentId instrument_id)
    cpdef dict get_books(self)
    cpdef list get_open_orders(self, InstrumentId instrument_id=*)
    cpdef list get_open_bid_orders(self, InstrumentId instrument_id=*)
    cpdef list get_open_ask_orders(self, InstrumentId instrument_id=*)
    cpdef Account get_account(self)

    cpdef void register_client(self, BacktestExecClient client) except *
    cpdef void set_fill_model(self, FillModel fill_model) except *
    cpdef void set_latency_model(self, LatencyModel latency_model) except *
    cpdef void initialize_account(self) except *
    cpdef void adjust_account(self, Money adjustment) except *
    cdef tuple generate_inflight_command(self, TradingCommand command)
    cpdef void send(self, TradingCommand command) except *
    cpdef void process_order_book(self, OrderBookData data) except *
    cpdef void process_quote_tick(self, QuoteTick tick) except *
    cpdef void process_trade_tick(self, TradeTick tick) except *
    cpdef void process_bar(self, Bar bar) except *
    cdef void _process_trade_ticks_from_bar(self, OrderBook book, Bar bar) except *
    cdef void _process_quote_ticks_from_bar(self, OrderBook book) except *
    cpdef void process(self, int64_t now_ns) except *
    cpdef void reset(self) except *

# -- COMMAND HANDLING -----------------------------------------------------------------------------

    cdef void _process_order(self, Order order) except *
    cdef void _process_market_order(self, MarketOrder order) except *
    cdef void _process_limit_order(self, LimitOrder order) except *
    cdef void _process_stop_market_order(self, Order order) except *
    cdef void _process_stop_limit_order(self, Order order) except *
    cdef void _update_limit_order(self, LimitOrder order, Quantity qty, Price price) except *
    cdef void _update_stop_market_order(self, Order order, Quantity qty, Price trigger_price) except *
    cdef void _update_stop_limit_order(self, Order order, Quantity qty, Price price, Price trigger_price) except *

# -- EVENT HANDLING -------------------------------------------------------------------------------

    cdef void _accept_order(self, Order order) except *
    cdef void _update_order(self, Order order, Quantity qty, Price price=*, Price trigger_price=*, bint update_ocos=*) except *
    cdef void _update_oco_orders(self, Order order) except *
    cdef void _cancel_order(self, Order order, bint cancel_ocos=*) except *
    cdef void _cancel_oco_orders(self, Order order) except *
    cdef void _expire_order(self, Order order) except *

# -- ORDER MATCHING ENGINE ------------------------------------------------------------------------

    cdef void _add_order(self, Order order) except *
    cdef void _delete_order(self, Order order) except *
    cdef void _iterate_matching_engine(self, InstrumentId instrument_id, int64_t timestamp_ns) except *
    cdef void _iterate_side(self, list orders, int64_t timestamp_ns) except *
    cdef void _match_order(self, Order order) except *
    cdef void _match_limit_order(self, LimitOrder order) except *
    cdef void _match_stop_market_order(self, Order order) except *
    cdef void _match_stop_limit_order(self, Order order) except *
    cdef bint _is_limit_marketable(self, InstrumentId instrument_id, OrderSide side, Price price) except *
    cdef bint _is_limit_matched(self, InstrumentId instrument_id, OrderSide side, Price price) except *
    cdef bint _is_stop_marketable(self, InstrumentId instrument_id, OrderSide side, Price price) except *
    cdef bint _is_stop_triggered(self, InstrumentId instrument_id, OrderSide side, Price price) except *
    cdef list _determine_limit_price_and_volume(self, Order order)
    cdef list _determine_market_price_and_volume(self, Order order)
    cdef void _fill_limit_order(self, Order order, LiquiditySide liquidity_side) except *
    cdef void _fill_market_order(self, Order order, LiquiditySide liquidity_side) except *
    cdef void _apply_fills(
        self,
        Order order,
        LiquiditySide liquidity_side,
        list fills,
        PositionId position_id,
        Position position,
    ) except *
    cdef void _fill_order(
        self,
        Instrument instrument,
        Order order,
        PositionId venue_position_id,
        Position position,
        Quantity last_qty,
        Price last_px,
        LiquiditySide liquidity_side,
    ) except *

# -- IDENTIFIER GENERATORS ------------------------------------------------------------------------

    cdef PositionId _get_position_id(self, Order order, bint generate=*)
    cdef PositionId _generate_venue_position_id(self, InstrumentId instrument_id)
    cdef VenueOrderId _generate_venue_order_id(self, InstrumentId instrument_id)
    cdef TradeId _generate_trade_id(self)

# -- EVENT GENERATORS -----------------------------------------------------------------------------

    cdef void _generate_fresh_account_state(self) except *
    cdef void _generate_order_submitted(self, Order order) except *
    cdef void _generate_order_rejected(self, Order order, str reason) except *
    cdef void _generate_order_accepted(self, Order order) except *
    cdef void _generate_order_pending_update(self, Order order) except *
    cdef void _generate_order_pending_cancel(self, Order order) except *
    cdef void _generate_order_modify_rejected(
        self,
        StrategyId strategy_id,
        InstrumentId instrument_id,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        str reason,
    ) except *
    cdef void _generate_order_cancel_rejected(
        self,
        StrategyId strategy_id,
        InstrumentId instrument_id,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        str reason,
    ) except *
    cdef void _generate_order_updated(self, Order order, Quantity qty, Price price, Price trigger_price) except *
    cdef void _generate_order_canceled(self, Order order) except *
    cdef void _generate_order_triggered(self, Order order) except *
    cdef void _generate_order_expired(self, Order order) except *
    cdef void _generate_order_filled(
        self,
        Order order,
        PositionId venue_position_id,
        Quantity last_qty,
        Price last_px,
        Currency quote_currency,
        Money commission,
        LiquiditySide liquidity_side
    ) except *
