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

"""
The `Strategy` class allows traders to implement their own customized trading strategies.

A user can inherit from `Strategy` and optionally override any of the
"on" named event methods. The class is not entirely initialized in a stand-alone
way, the intended usage is to pass strategies to a `Trader` so that they can be
fully "wired" into the platform. Exceptions will be raised if a `Strategy`
attempts to operate without a managing `Trader` instance.

"""

import warnings
from typing import Dict, Optional, Set

import cython

from nautilus_trader.config import ActorConfig
from nautilus_trader.persistence.streaming import generate_signal_class

from cpython.datetime cimport datetime
from libc.stdint cimport int64_t

from nautilus_trader.cache.base cimport CacheFacade
from nautilus_trader.common.clock cimport Clock
from nautilus_trader.common.clock cimport LiveClock
from nautilus_trader.common.component cimport Component
from nautilus_trader.common.logging cimport CMD
from nautilus_trader.common.logging cimport REQ
from nautilus_trader.common.logging cimport SENT
from nautilus_trader.common.logging cimport Logger
from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.data cimport Data
from nautilus_trader.core.message cimport Event
from nautilus_trader.data.messages cimport DataRequest
from nautilus_trader.data.messages cimport DataResponse
from nautilus_trader.data.messages cimport Subscribe
from nautilus_trader.data.messages cimport Unsubscribe
from nautilus_trader.model.c_enums.book_type cimport BookType
from nautilus_trader.model.data.bar cimport Bar
from nautilus_trader.model.data.bar cimport BarType
from nautilus_trader.model.data.base cimport DataType
from nautilus_trader.model.data.tick cimport QuoteTick
from nautilus_trader.model.data.tick cimport TradeTick
from nautilus_trader.model.data.ticker cimport Ticker
from nautilus_trader.model.data.venue cimport InstrumentClosePrice
from nautilus_trader.model.data.venue cimport InstrumentStatusUpdate
from nautilus_trader.model.data.venue cimport VenueStatusUpdate
from nautilus_trader.model.identifiers cimport ClientId
from nautilus_trader.model.identifiers cimport ComponentId
from nautilus_trader.model.identifiers cimport InstrumentId
from nautilus_trader.model.identifiers cimport TraderId
from nautilus_trader.model.identifiers cimport Venue
from nautilus_trader.model.instruments.base cimport Instrument
from nautilus_trader.model.orderbook.data cimport OrderBookData
from nautilus_trader.model.orderbook.data cimport OrderBookSnapshot
from nautilus_trader.msgbus.bus cimport MessageBus


cdef class Actor(Component):
    """
    The abstract base class for all actor components.

    Parameters
    ----------
    config : ActorConfig, optional
        The actor configuration.

    Raises
    ------
    TypeError
        If `config` is not of type `ActorConfig`.

    Warnings
    --------
    This class should not be used directly, but through a concrete subclass.
    """

    def __init__(self, config: Optional[ActorConfig]=None):
        if config is None:
            config = ActorConfig()
        Condition.type(config, ActorConfig, "config")

        if config.component_id is not None:
            component_id = ComponentId(config.component_id)
        else:
            component_id = None

        clock = LiveClock()
        super().__init__(
            clock=clock,
            logger=Logger(clock=clock),
            component_id=component_id,
            config=config.dict(),
        )

        self._warning_events: Set[type] = set()
        self._signal_classes: Dict[str, type] = {}

        self.trader_id = None  # Initialized when registered
        self.msgbus = None     # Initialized when registered
        self.cache = None      # Initialized when registered
        self.clock = None      # Initialized when registered
        self.log = self._log

# -- ABSTRACT METHODS -----------------------------------------------------------------------------

    cpdef void on_start(self) except *:
        """
        Actions to be performed on start.

        The intent is that this method is called once per fresh trading session
        when the component is initially started.

        It is recommended to subscribe/request data here.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_start was called when not overridden")

    cpdef void on_stop(self) except *:
        """
        Actions to be performed on stopped.

        The intent is that this method is called every time the strategy is
        paused, and also when it is done for day.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_stop was called when not overridden")

    cpdef void on_resume(self) except *:
        """
        Actions to be performed on resume.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_reset(self) except *:
        """
        Actions to be performed on reset.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_reset was called when not overridden")

    cpdef void on_dispose(self) except *:
        """
        Actions to be performed on dispose.

        Cleanup any resources used by the strategy here.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_dispose was called when not overridden")

    cpdef void on_degrade(self) except *:
        """
        Actions to be performed on degrade.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_degrade was called when not overridden")

    cpdef void on_fault(self) except *:
        """
        Actions to be performed on fault.

        Cleanup any resources used by the actor here.

        Warnings
        --------
        System method (not intended to be called by user code).

        Should be overridden in the actor implementation.

        """
        # Should override in subclass
        warnings.warn("on_fault was called when not overridden")

    cpdef void on_instrument(self, Instrument instrument) except *:
        """
        Actions to be performed when running and receives an instrument.

        Parameters
        ----------
        instrument : Instrument
            The instrument received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_order_book(self, OrderBook order_book) except *:
        """
        Actions to be performed when running and receives an order book snapshot.

        Parameters
        ----------
        order_book : OrderBook
            The order book received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_order_book_delta(self, OrderBookData delta) except *:
        """
        Actions to be performed when running and receives an order book delta.

        Parameters
        ----------
        delta : OrderBookDelta, OrderBookDeltas, OrderBookSnapshot
            The order book delta received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_ticker(self, Ticker ticker) except *:
        """
        Actions to be performed when running and receives a ticker.

        Parameters
        ----------
        ticker : Ticker
            The ticker received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_quote_tick(self, QuoteTick tick) except *:
        """
        Actions to be performed when running and receives a quote tick.

        Parameters
        ----------
        tick : QuoteTick
            The tick received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_trade_tick(self, TradeTick tick) except *:
        """
        Actions to be performed when running and receives a trade tick.

        Parameters
        ----------
        tick : TradeTick
            The tick received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_bar(self, Bar bar) except *:
        """
        Actions to be performed when running and receives a bar.

        Parameters
        ----------
        bar : Bar
            The bar received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_venue_status_update(self, VenueStatusUpdate update) except *:
        """
        Actions to be performed when running and receives a venue status update.

        Parameters
        ----------
        update : VenueStatusUpdate
            The update received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_instrument_status_update(self, InstrumentStatusUpdate update) except *:
        """
        Actions to be performed when running and receives an instrument status
        update.

        Parameters
        ----------
        update : InstrumentStatusUpdate
            The update received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_instrument_close_price(self, InstrumentClosePrice update) except *:
        """
        Actions to be performed when running and receives an instrument close
        price update.

        Parameters
        ----------
        update : InstrumentClosePrice
            The update received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_data(self, Data data) except *:
        """
        Actions to be performed when running and receives generic data.

        Parameters
        ----------
        data : Data
            The data received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

    cpdef void on_event(self, Event event) except *:
        """
        Actions to be performed running and receives an event.

        Parameters
        ----------
        event : Event
            The event received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        pass  # Optionally override in subclass

# -- REGISTRATION ---------------------------------------------------------------------------------

    cpdef void register_base(
        self,
        TraderId trader_id,
        MessageBus msgbus,
        CacheFacade cache,
        Clock clock,
        Logger logger,
    ) except *:
        """
        Register the component with a trader.

        Parameters
        ----------
        trader_id : TraderId
            The trader ID for the actor.
        msgbus : MessageBus
            The message bus for the actor.
        cache : CacheFacade
            The read-only cache for the actor.
        clock : Clock
            The clock for the actor.
        logger : Logger
            The logger for the actor.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(trader_id, "trader_id")
        Condition.not_none(msgbus, "msgbus")
        Condition.not_none(cache, "cache")
        Condition.not_none(clock, "clock")
        Condition.not_none(logger, "logger")

        clock.register_default_handler(self.handle_event)
        self._change_clock(clock)
        self._change_logger(logger)
        self._change_msgbus(msgbus)  # The trader ID is also assigned here

        self.trader_id = trader_id
        self.msgbus = msgbus
        self.cache = cache
        self.clock = self._clock
        self.log = self._log

    cpdef void register_warning_event(self, type event) except *:
        """
        Register the given event type for warning log levels.

        Parameters
        ----------
        event : type
            The event class to register.

        """
        Condition.not_none(event, "event")

        self._warning_events.add(event)

        self._log.debug(f"Registered `{event.__name__}` for warning log levels.")

    cpdef void deregister_warning_event(self, type event) except *:
        """
        Deregister the given event type from warning log levels.

        Parameters
        ----------
        event : type
            The event class to deregister.

        """
        Condition.not_none(event, "event")

        self._warning_events.discard(event)

        self._log.debug(f"Deregistered `{event.__name__}` from warning log levels.")

# -- ACTION IMPLEMENTATIONS -----------------------------------------------------------------------

    cpdef void _start(self) except *:
        self.on_start()

    cpdef void _stop(self) except *:
        # Clean up clock
        cdef list timer_names = self._clock.timer_names()
        self._clock.cancel_timers()

        cdef str name
        for name in timer_names:
            self._log.info(f"Cancelled Timer(name={name}).")

        self.on_stop()

    cpdef void _resume(self) except *:
        self.on_resume()

    cpdef void _reset(self) except *:
        self.on_reset()

    cpdef void _dispose(self) except *:
        self.on_dispose()

    cpdef void _degrade(self) except *:
        self.on_degrade()

    cpdef void _fault(self) except *:
        self.on_fault()

# -- SUBSCRIPTIONS --------------------------------------------------------------------------------

    cpdef void subscribe_data(self, DataType data_type, ClientId client_id=None) except *:
        """
        Subscribe to data of the given data type.

        Parameters
        ----------
        data_type : DataType
            The data type to subscribe to.
        client_id : ClientId, optional
            The data client ID. If supplied then a `Subscribe` command will be
            sent to the corresponding data client.

        """
        Condition.not_none(data_type, "data_type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.{data_type.topic}",
            handler=self.handle_data,
        )

        if client_id is None:
            return

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=None,
            data_type=data_type,
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_instrument(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to update `Instrument` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The instrument ID for the subscription.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.instrument"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_instrument,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(Instrument, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_instruments(self, Venue venue, ClientId client_id=None) except *:
        """
        Subscribe to update `Instrument` data for the given venue.

        Parameters
        ----------
        venue : Venue
            The venue for the subscription.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue.

        """
        Condition.not_none(venue, "venue")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.instrument.{venue}.*",
            handler=self.handle_instrument,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=venue,
            data_type=DataType(Instrument),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_order_book_deltas(
        self,
        InstrumentId instrument_id,
        BookType book_type=BookType.L2_MBP,
        int depth=0,
        dict kwargs=None,
        ClientId client_id=None,
    ) except *:
        """
        Subscribe to the order book deltas stream, being a snapshot then deltas
        `OrderBookData` for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The order book instrument ID to subscribe to.
        book_type : BookType {``L1_TBBO``, ``L2_MBP``, ``L3_MBO``}
            The order book type.
        depth : int, optional
            The maximum depth for the order book. A depth of 0 is maximum depth.
        kwargs : dict, optional
            The keyword arguments for exchange specific parameters.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.book.deltas"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_order_book_delta,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(OrderBookData, metadata={
                "instrument_id": instrument_id,
                "book_type": book_type,
                "depth": depth,
                "kwargs": kwargs,
            }),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_order_book_snapshots(
        self,
        InstrumentId instrument_id,
        BookType book_type=BookType.L2_MBP,
        int depth=0,
        int interval_ms=1000,
        dict kwargs=None,
        ClientId client_id=None,
    ) except *:
        """
        Subscribe to `OrderBook` snapshots for the given instrument ID.

        The `DataEngine` will only maintain one order book for each instrument.
        Because of this - the level, depth and kwargs for the stream will be set
        as per the last subscription request (this will also affect all subscribers).

        Parameters
        ----------
        instrument_id : InstrumentId
            The order book instrument ID to subscribe to.
        book_type : BookType {``L1_TBBO``, ``L2_MBP``, ``L3_MBO``}
            The order book type.
        depth : int, optional
            The maximum depth for the order book. A depth of 0 is maximum depth.
        interval_ms : int
            The order book snapshot interval in milliseconds.
        kwargs : dict, optional
            The keyword arguments for exchange specific parameters.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        Raises
        ------
        ValueError
            If `depth` is negative (< 0).
        ValueError
            If `interval_ms` is not positive (> 0).

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.not_negative(depth, "depth")
        Condition.not_negative(interval_ms, "interval_ms")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        if book_type == BookType.L1_TBBO and depth > 1:
            self._log.error(
                "Cannot subscribe to order book snapshots: "
                f"L1 TBBO book subscription depth > 1, was {depth}",
            )
            return

        self._msgbus.subscribe(
            topic=f"data.book.snapshots"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}"
                  f".{interval_ms}",
            handler=self.handle_order_book,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(OrderBookSnapshot, metadata={
                "instrument_id": instrument_id,
                "book_type": book_type,
                "depth": depth,
                "interval_ms": interval_ms,
                "kwargs": kwargs,
            }),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_ticker(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to streaming `Ticker` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.tickers"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_ticker,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(Ticker, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_quote_ticks(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to streaming `QuoteTick` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.quotes"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_quote_tick,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(QuoteTick, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_trade_ticks(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to streaming `TradeTick` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.trades"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_trade_tick,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(TradeTick, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_bars(self, BarType bar_type, ClientId client_id=None) except *:
        """
        Subscribe to streaming `Bar` data for the given bar type.

        Parameters
        ----------
        bar_type : BarType
            The bar type to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(bar_type, "bar_type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.bars.{bar_type}",
            handler=self.handle_bar,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=bar_type.instrument_id.venue,
            data_type=DataType(Bar, metadata={"bar_type": bar_type}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_venue_status_updates(self, Venue venue, ClientId client_id=None) except *:
        """
        Subscribe to status updates of the given venue.

        Parameters
        ----------
        venue : Venue
            The venue to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue.

        """
        Condition.not_none(venue, "venue")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.venue.status",
            handler=self.handle_venue_status_update,
        )

    cpdef void subscribe_instrument_status_updates(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to status updates of the given instrument id.

        Parameters
        ----------
        instrument_id : InstrumentId
            The instrument to subscribe to status updates for.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.venue.status",
            handler=self.handle_instrument_status_update,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(InstrumentStatusUpdate, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void subscribe_instrument_close_prices(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Subscribe to closing prices for the given instrument id.

        Parameters
        ----------
        instrument_id : InstrumentId
            The instrument to subscribe to status updates for.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.subscribe(
            topic=f"data.venue.close_price.{instrument_id.value}",
            handler=self.handle_instrument_close_price,
        )

        cdef Subscribe command = Subscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(InstrumentClosePrice, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_data(self, DataType data_type, ClientId client_id=None) except *:
        """
        Unsubscribe from data of the given data type.

        Parameters
        ----------
        data_type : DataType
            The data type to unsubscribe from.
        client_id : ClientId, optional
            The data client ID. If supplied then an `Unsubscribe` command will
            be sent to the data client.

        """
        Condition.not_none(data_type, "data_type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.{data_type.topic}",
            handler=self.handle_data,
        )

        if client_id is None:
            return

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=None,
            data_type=data_type,
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_instruments(self, Venue venue, ClientId client_id=None) except *:
        """
        Unsubscribe from update `Instrument` data for the given venue.

        Parameters
        ----------
        venue : Venue
            The venue for the subscription.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue.

        """
        Condition.not_none(venue, "venue")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.instrument.{venue}.*",
            handler=self.handle_instrument,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=venue,
            data_type=DataType(Instrument),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_instrument(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Unsubscribe from update `Instrument` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The instrument to unsubscribe from.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.instrument"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_instrument,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(Instrument, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_order_book_deltas(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Unsubscribe the order book deltas stream for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The order book instrument to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.book.deltas"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_order_book_delta,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(OrderBookData, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_order_book_snapshots(
        self,
        InstrumentId instrument_id,
        int interval_ms=1000,
        ClientId client_id=None,
    ) except *:
        """
        Unsubscribe from order book snapshots for the given instrument ID.

        The interval must match the previously subscribed interval.

        Parameters
        ----------
        instrument_id : InstrumentId
            The order book instrument to subscribe to.
        interval_ms : int
            The order book snapshot interval in milliseconds.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.book.snapshots"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}"
                  f".{interval_ms}",
            handler=self.handle_order_book,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(OrderBookSnapshot, metadata={
                "instrument_id": instrument_id,
                "interval_ms": interval_ms,
            }),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_ticker(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Unsubscribe from streaming `Ticker` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument to unsubscribe from.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.tickers"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_ticker,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(Ticker, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_quote_ticks(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Unsubscribe from streaming `QuoteTick` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument to unsubscribe from.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.quotes"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_quote_tick,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(QuoteTick, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_trade_ticks(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Unsubscribe from streaming `TradeTick` data for the given instrument ID.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument ID to unsubscribe from.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.trades"
                  f".{instrument_id.venue}"
                  f".{instrument_id.symbol}",
            handler=self.handle_trade_tick,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(TradeTick, metadata={"instrument_id": instrument_id}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)

    cpdef void unsubscribe_bars(self, BarType bar_type, ClientId client_id=None) except *:
        """
        Unsubscribe from streaming `Bar` data for the given bar type.

        Parameters
        ----------
        bar_type : BarType
            The bar type to unsubscribe from.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(bar_type, "bar_type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.bars.{bar_type}",
            handler=self.handle_bar,
        )

        cdef Unsubscribe command = Unsubscribe(
            client_id=client_id,
            venue=bar_type.instrument_id.venue,
            data_type=DataType(Bar, metadata={"bar_type": bar_type}),
            command_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_cmd(command)
        self._log.info(f"Unsubscribed from {bar_type} bar data.")

    cpdef void unsubscribe_venue_status_updates(self, Venue venue, ClientId client_id=None) except *:
        """
        Unsubscribe to status updates of the given venue.

        Parameters
        ----------
        venue : Venue
            The venue to subscribe to.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue.

        """
        Condition.not_none(venue, "venue")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.unsubscribe(
            topic=f"data.venue.status",
            handler=self.handle_venue_status_update,
        )

    cpdef void publish_data(self, DataType data_type, Data data) except *:
        """
        Publish the given data to the message bus.

        Parameters
        ----------
        data_type : DataType
            The data type being published.
        data : Data
            The data to publish.

        """
        Condition.not_none(data_type, "data_type")
        Condition.not_none(data, "data")
        Condition.type(data, data_type.type, "data", "data.type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        self._msgbus.publish_c(topic=f"data.{data_type.topic}", msg=data)

    cpdef void publish_signal(self, str name, value, int64_t ts_event = 0, bint stream = False) except *:
        """
        Publish the given value as a signal to the message bus. Optionally setup persistence for this `signal`.

        Parameters
        ----------
        name : str
            The name of the signal being published.
        value : object
            The signal data to publish.
        ts_event : int64, optional
            The UNIX timestamp (nanoseconds) when the signal event occurred.
            If ``None`` then will timestamp current time.
        stream : bool, default False
            If the signal should also be streamed for persistence.

        """
        Condition.not_none(name, "name")
        Condition.not_none(value, "value")
        Condition.is_in(type(value), (int, float, str), "value", "int, float, str")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        cdef type cls = self._signal_classes.get(name)
        if cls is None:
            cls = generate_signal_class(name=name)
            self._signal_classes[name] = cls

        cdef int64_t now = self.clock.timestamp_ns()
        cdef Data data = cls(
            value=value,
            ts_event=ts_event or now,
            ts_init=now,
        )
        self.publish_data(data_type=DataType(cls), data=data)

# -- REQUESTS -------------------------------------------------------------------------------------

    cpdef void request_data(self, ClientId client_id, DataType data_type) except *:
        """
        Request custom data for the given data type from the given data client.

        Parameters
        ----------
        client_id : ClientId
            The data client ID.
        data_type : DataType
            The data type for the request.

        """
        Condition.not_none(client_id, "client_id")
        Condition.not_none(data_type, "data_type")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        cdef DataRequest request = DataRequest(
            client_id=client_id,
            venue=None,
            data_type=data_type,
            callback=self._handle_data_response,
            request_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_req(request)

    cpdef void request_instrument(self, InstrumentId instrument_id, ClientId client_id=None) except *:
        """
        Request an instrument for the given parameters.

        Parameters
        ----------
        instrument_id : InstrumentId
            The instrument ID for the request.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        """
        Condition.not_none(instrument_id, "instrument_id")

        cdef DataRequest request = DataRequest(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(Instrument, metadata={
                "instrument_id": instrument_id,
            }),
            callback=self._handle_instrument_response,
            request_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_req(request)

    cpdef void request_quote_ticks(
        self,
        InstrumentId instrument_id,
        datetime from_datetime=None,
        datetime to_datetime=None,
        ClientId client_id=None,
    ) except *:
        """
        Request historical quote ticks for the given parameters.

        If `to_datetime` is ``None`` then will request up to the most recent data.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument ID for the request.
        from_datetime : datetime, optional
            The specified from datetime for the data.
        to_datetime : datetime, optional
            The specified to datetime for the data. If ``None`` then will default
            to the current datetime.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        Notes
        -----
        Always limited to the tick capacity of the `DataEngine` cache.

        """
        Condition.not_none(instrument_id, "instrument_id")
        if from_datetime is not None and to_datetime is not None:
            Condition.true(from_datetime < to_datetime, "from_datetime was >= to_datetime")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        cdef DataRequest request = DataRequest(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(QuoteTick, metadata={
                "instrument_id": instrument_id,
                "from_datetime": from_datetime,
                "to_datetime": to_datetime,
            }),
            callback=self._handle_quote_ticks_response,
            request_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_req(request)

    cpdef void request_trade_ticks(
        self,
        InstrumentId instrument_id,
        datetime from_datetime=None,
        datetime to_datetime=None,
        ClientId client_id=None,
    ) except *:
        """
        Request historical trade ticks for the given parameters.

        If `to_datetime` is ``None`` then will request up to the most recent data.

        Parameters
        ----------
        instrument_id : InstrumentId
            The tick instrument ID for the request.
        from_datetime : datetime, optional
            The specified from datetime for the data.
        to_datetime : datetime, optional
            The specified to datetime for the data. If ``None`` then will default
            to the current datetime.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        Notes
        -----
        Always limited to the tick capacity of the `DataEngine` cache.

        """
        Condition.not_none(instrument_id, "instrument_id")
        if from_datetime is not None and to_datetime is not None:
            Condition.true(from_datetime < to_datetime, "from_datetime was >= to_datetime")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        cdef DataRequest request = DataRequest(
            client_id=client_id,
            venue=instrument_id.venue,
            data_type=DataType(TradeTick, metadata={
                "instrument_id": instrument_id,
                "from_datetime": from_datetime,
                "to_datetime": to_datetime,
            }),
            callback=self._handle_trade_ticks_response,
            request_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_req(request)

    cpdef void request_bars(
        self,
        BarType bar_type,
        datetime from_datetime=None,
        datetime to_datetime=None,
        ClientId client_id=None,
    ) except *:
        """
        Request historical bars for the given parameters.

        If `to_datetime` is ``None`` then will request up to the most recent data.

        Parameters
        ----------
        bar_type : BarType
            The bar type for the request.
        from_datetime : datetime, optional
            The specified from datetime for the data.
        to_datetime : datetime, optional
            The specified to datetime for the data. If ``None`` then will default
            to the current datetime.
        client_id : ClientId, optional
            The specific client ID for the command.
            If ``None`` then will be inferred from the venue in the instrument ID.

        Raises
        ------
        ValueError
            If `from_datetime` is not less than `to_datetime`.

        Notes
        -----
        Always limited to the bar capacity of the `DataEngine` cache.

        """
        Condition.not_none(bar_type, "bar_type")
        if from_datetime is not None and to_datetime is not None:
            Condition.true(from_datetime < to_datetime, "from_datetime was >= to_datetime")
        Condition.true(self.trader_id is not None, "The actor has not been registered")

        cdef DataRequest request = DataRequest(
            client_id=client_id,
            venue=bar_type.instrument_id.venue,
            data_type=DataType(Bar, metadata={
                "bar_type": bar_type,
                "from_datetime": from_datetime,
                "to_datetime": to_datetime,
                "limit": self.cache.bar_capacity,
            }),
            callback=self._handle_bars_response,
            request_id=self._uuid_factory.generate(),
            ts_init=self._clock.timestamp_ns(),
        )

        self._send_data_req(request)

# -- HANDLERS -------------------------------------------------------------------------------------

    cpdef void handle_instrument(self, Instrument instrument) except *:
        """
        Handle the given instrument.

        Calls `on_instrument` if state is ``RUNNING``.

        Parameters
        ----------
        instrument : Instrument
            The received instrument.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(instrument, "instrument")

        if self.is_running_c():
            try:
                self.on_instrument(instrument)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(instrument)}", ex)
                raise

    cpdef void handle_order_book_delta(self, OrderBookData delta) except *:
        """
        Handle the given order book data.

        Calls `on_order_book_delta` if state is ``RUNNING``.

        Parameters
        ----------
        delta : OrderBookDelta, OrderBookDeltas, OrderBookSnapshot
            The order book delta received.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(delta, "data")

        if self.is_running_c():
            try:
                self.on_order_book_delta(delta)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(delta)}", ex)
                raise

    cpdef void handle_order_book(self, OrderBook order_book) except *:
        """
        Handle the given order book snapshot.

        Calls `on_order_book` if state is ``RUNNING``.

        Parameters
        ----------
        order_book : OrderBook
            The received order book.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(order_book, "order_book")

        if self.is_running_c():
            try:
                self.on_order_book(order_book)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(order_book)}", ex)
                raise

    cpdef void handle_ticker(self, Ticker ticker, bint is_historical=False) except *:
        """
        Handle the given ticker.

        Calls `on_ticker` if state is ``RUNNING``.

        Parameters
        ----------
        ticker : Ticker
            The received ticker.
        is_historical : bool
            If ticker is historical then it won't be passed to `on_ticker`.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(ticker, "ticker")

        if is_historical:
            return  # Don't pass to on_ticker()

        if self.is_running_c():
            try:
                self.on_ticker(ticker)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(ticker)}", ex)
                raise

    cpdef void handle_quote_tick(self, QuoteTick tick, bint is_historical=False) except *:
        """
        Handle the given tick.

        Calls `on_quote_tick` if state is ``RUNNING``.

        Parameters
        ----------
        tick : QuoteTick
            The received tick.
        is_historical : bool
            If tick is historical then it won't be passed to `on_quote_tick`.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(tick, "tick")

        if is_historical:
            return  # Don't pass to on_quote_tick()

        if self.is_running_c():
            try:
                self.on_quote_tick(tick)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(tick)}", ex)
                raise

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef void handle_quote_ticks(self, list ticks) except *:
        """
        Handle the given tick data by handling each tick individually.

        Parameters
        ----------
        ticks : list[QuoteTick]
            The received ticks.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(ticks, "ticks")  # Could be empty

        cdef int length = len(ticks)
        cdef QuoteTick first = ticks[0] if length > 0 else None
        cdef InstrumentId instrument_id = first.instrument_id if first is not None else None

        if length > 0:
            self._log.info(f"Received <QuoteTick[{length}]> data for {instrument_id}.")
        else:
            self._log.warning("Received <QuoteTick[]> data with no ticks.")

        for i in range(length):
            self.handle_quote_tick(ticks[i], is_historical=True)

    cpdef void handle_trade_tick(self, TradeTick tick, bint is_historical=False) except *:
        """
        Handle the given tick.

        Calls `on_trade_tick` if state is ``RUNNING``.

        Parameters
        ----------
        tick : TradeTick
            The received trade tick.
        is_historical : bool
            If tick is historical then it won't be passed to `on_trade_tick`.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(tick, "tick")

        if is_historical:
            return  # Don't pass to on_trade_tick()

        if self.is_running_c():
            try:
                self.on_trade_tick(tick)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(tick)}", ex)
                raise

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef void handle_trade_ticks(self, list ticks) except *:
        """
        Handle the given tick data by handling each tick individually.

        Parameters
        ----------
        ticks : list[TradeTick]
            The received ticks.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(ticks, "ticks")  # Could be empty

        cdef int length = len(ticks)
        cdef TradeTick first = ticks[0] if length > 0 else None
        cdef InstrumentId instrument_id = first.instrument_id if first is not None else None

        if length > 0:
            self._log.info(f"Received <TradeTick[{length}]> data for {instrument_id}.")
        else:
            self._log.warning("Received <TradeTick[]> data with no ticks.")

        for i in range(length):
            self.handle_trade_tick(ticks[i], is_historical=True)

    cpdef void handle_bar(self, Bar bar, bint is_historical=False) except *:
        """
        Handle the given bar data.

        Calls `on_bar` if state is ``RUNNING``.

        Parameters
        ----------
        bar : Bar
            The bar received.
        is_historical : bool
            If bar is historical then it won't be passed to `on_bar`.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(bar, "bar")

        if is_historical:
            return  # Don't pass to on_bar()

        if self.is_running_c():
            try:
                self.on_bar(bar)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(bar)}", ex)
                raise

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef void handle_bars(self, list bars) except *:
        """
        Handle the given bar data by handling each bar individually.

        Parameters
        ----------
        bars : list[Bar]
            The bars to handle.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(bars, "bars")  # Can be empty

        cdef int length = len(bars)
        cdef Bar first = bars[0] if length > 0 else None
        cdef Bar last = bars[length - 1] if length > 0 else None

        if length > 0:
            self._log.info(f"Received <Bar[{length}]> data for {first.type}.")
        else:
            self._log.error(f"Received <Bar[{length}]> data for unknown bar type.")
            return  # TODO: Strategy shouldn't receive zero bars

        if length > 0 and first.ts_init > last.ts_init:
            raise RuntimeError(f"cannot handle <Bar[{length}]> data: incorrectly sorted")

        for i in range(length):
            self.handle_bar(bars[i], is_historical=True)

    cpdef void handle_venue_status_update(self, VenueStatusUpdate update) except *:
        """
        Handle the given venue status update.

        Calls `on_venue_status_update` if state is ``RUNNING``.

        Parameters
        ----------
        update : VenueStatusUpdate
            The received update.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(update, "update")

        if self.is_running_c():
            try:
                self.on_venue_status_update(update)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(update)}", ex)
                raise

    cpdef void handle_instrument_status_update(self, InstrumentStatusUpdate update) except *:
        """
        Handle the given instrument status update.

        Calls `on_instrument_status_update` if state is ``RUNNING``.

        Parameters
        ----------
        update : InstrumentStatusUpdate
            The received update.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(update, "update")

        if self.is_running_c():
            try:
                self.on_instrument_status_update(update)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(update)}", ex)
                raise

    cpdef void handle_instrument_close_price(self, InstrumentClosePrice update) except *:
        """
        Handle the given instrument close price update.

        Calls `on_instrument_close_price` if .state is ``RUNNING``.

        Parameters
        ----------
        update : InstrumentClosePrice
            The received update.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(update, "update")

        if self.is_running_c():
            try:
                self.on_instrument_close_price(update)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(update)}", ex)
                raise

    cpdef void handle_data(self, Data data) except *:
        """
        Handle the given data.

        Calls `on_data` if state is ``RUNNING``.

        Parameters
        ----------
        data : Data
            The received data.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(data, "data")

        if self.is_running_c():
            try:
                self.on_data(data)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(data)}", ex)
                raise

    cpdef void handle_event(self, Event event) except *:
        """
        Handle the given event.

        Calls `on_event` if state is ``RUNNING``.

        Parameters
        ----------
        event : Event
            The received event.

        Warnings
        --------
        System method (not intended to be called by user code).

        """
        Condition.not_none(event, "event")

        if self.is_running_c():
            try:
                self.on_event(event)
            except Exception as ex:
                self._log.exception(f"Error on handling {repr(event)}", ex)
                raise

    cpdef void _handle_data_response(self, DataResponse response) except *:
        self.handle_data(response.data)

    cpdef void _handle_instrument_response(self, DataResponse response) except *:
        self.handle_instrument(response.data)

    cpdef void _handle_quote_ticks_response(self, DataResponse response) except *:
        self.handle_quote_ticks(response.data)

    cpdef void _handle_trade_ticks_response(self, DataResponse response) except *:
        self.handle_trade_ticks(response.data)

    cpdef void _handle_bars_response(self, DataResponse response) except *:
        self.handle_bars(response.data)

# -- EGRESS ---------------------------------------------------------------------------------------

    cdef void _send_data_cmd(self, DataCommand command) except *:
        if not self._log.is_bypassed:
            self._log.info(f"{CMD}{SENT} {command}.")
        self._msgbus.send(endpoint="DataEngine.execute", msg=command)

    cdef void _send_data_req(self, DataRequest request) except *:
        if not self._log.is_bypassed:
            self._log.info(f"{REQ}{SENT} {request}.")
        self._msgbus.request(endpoint="DataEngine.request", request=request)
