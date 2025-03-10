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
from libc.stdint cimport uint8_t
from libc.stdint cimport uint64_t

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.data cimport Data
from nautilus_trader.core.rust.model cimport quote_tick_free
from nautilus_trader.core.rust.model cimport quote_tick_from_raw
from nautilus_trader.core.rust.model cimport trade_tick_free
from nautilus_trader.core.rust.model cimport trade_tick_from_raw
from nautilus_trader.model.c_enums.aggressor_side cimport AggressorSide
from nautilus_trader.model.c_enums.aggressor_side cimport AggressorSideParser
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.c_enums.price_type cimport PriceType
from nautilus_trader.model.c_enums.price_type cimport PriceTypeParser
from nautilus_trader.model.identifiers cimport InstrumentId
from nautilus_trader.model.objects cimport Price
from nautilus_trader.model.objects cimport Quantity


cdef class QuoteTick(Data):
    """
    Represents a single quote tick in a financial market.

    Contains information about the best top of book bid and ask.

    Parameters
    ----------
    instrument_id : InstrumentId
        The quotes instrument ID.
    bid : Price
        The top of book bid price.
    ask : Price
        The top of book ask price.
    bid_size : Quantity
        The top of book bid size.
    ask_size : Quantity
        The top of book ask size.
    ts_event: int64
        The UNIX timestamp (nanoseconds) when the tick event occurred.
    ts_init: int64
        The UNIX timestamp (nanoseconds) when the data object was initialized.
    """

    def __init__(
        self,
        InstrumentId instrument_id not None,
        Price bid not None,
        Price ask not None,
        Quantity bid_size not None,
        Quantity ask_size not None,
        int64_t ts_event,
        int64_t ts_init,
    ):
        super().__init__(ts_event, ts_init)

        self._mem = quote_tick_from_raw(
            instrument_id._mem,
            bid._mem.raw,
            ask._mem.raw,
            bid._mem.precision,
            bid_size._mem.raw,
            ask_size._mem.raw,
            bid_size._mem.precision,
            ts_event,
            ts_init,
        )

    def __del__(self) -> None:
        quote_tick_free(self._mem)  # `self._mem` moved to Rust (then dropped)

    def __eq__(self, QuoteTick other) -> bool:
        return QuoteTick.to_dict_c(self) == QuoteTick.to_dict_c(other)

    def __hash__(self) -> int:
        return hash(frozenset(QuoteTick.to_dict_c(self)))

    def __str__(self) -> str:
        return (
            f"{self.instrument_id},"
            f"{self.bid},"
            f"{self.ask},"
            f"{self.bid_size},"
            f"{self.ask_size},"
            f"{self.ts_event}"
        )

    def __repr__(self) -> str:
        return f"{type(self).__name__}({self})"

    @staticmethod
    cdef QuoteTick from_raw_c(
        InstrumentId instrument_id,
        int64_t raw_bid,
        int64_t raw_ask,
        uint8_t price_prec,
        uint64_t raw_bid_size,
        uint64_t raw_ask_size,
        uint8_t size_prec,
        uint64_t ts_event,
        uint64_t ts_init,
    ):
        cdef QuoteTick tick = QuoteTick.__new__(QuoteTick)
        tick.ts_event = ts_event
        tick.ts_init = ts_init
        tick._mem = quote_tick_from_raw(
            instrument_id._mem,
            raw_bid,
            raw_ask,
            price_prec,
            raw_bid_size,
            raw_ask_size,
            size_prec,
            ts_event,
            ts_init,
        )

        return tick

    @property
    def instrument_id(self) -> InstrumentId:
        """
        The tick instrument ID.

        Returns
        -------
        Price

        """
        return InstrumentId.from_raw_c(self._mem.instrument_id)

    @property
    def bid(self) -> Price:
        """
        The top of book bid price.

        Returns
        -------
        Price

        """
        return Price.from_raw_c(self._mem.bid.raw, self._mem.bid.precision)

    @property
    def ask(self) -> Price:
        """
        The top of book ask price.

        Returns
        -------
        Price

        """
        return Price.from_raw_c(self._mem.ask.raw, self._mem.ask.precision)

    @property
    def bid_size(self) -> Quantity:
        """
        The top of book bid size.

        Returns
        -------
        Quantity

        """
        return Quantity.from_raw_c(self._mem.bid_size.raw, self._mem.bid_size.precision)

    @property
    def ask_size(self) -> Quantity:
        """
        The top of book ask size.

        Returns
        -------
        Quantity

        """
        return Quantity.from_raw_c(self._mem.ask_size.raw, self._mem.ask_size.precision)

    @staticmethod
    cdef QuoteTick from_dict_c(dict values):
        Condition.not_none(values, "values")
        return QuoteTick(
            instrument_id=InstrumentId.from_str_c(values["instrument_id"]),
            bid=Price.from_str_c(values["bid"]),
            ask=Price.from_str_c(values["ask"]),
            bid_size=Quantity.from_str_c(values["bid_size"]),
            ask_size=Quantity.from_str_c(values["ask_size"]),
            ts_event=values["ts_event"],
            ts_init=values["ts_init"],
        )

    @staticmethod
    cdef dict to_dict_c(QuoteTick obj):
        Condition.not_none(obj, "obj")
        return {
            "type": type(obj).__name__,
            "instrument_id": obj.instrument_id.value,
            "bid": str(obj.bid),
            "ask": str(obj.ask),
            "bid_size": str(obj.bid_size),
            "ask_size": str(obj.ask_size),
            "ts_event": obj.ts_event,
            "ts_init": obj.ts_init,
        }

    @staticmethod
    def from_raw(
        InstrumentId instrument_id,
        int64_t raw_bid,
        int64_t raw_ask,
        uint8_t price_prec,
        uint64_t raw_bid_size,
        uint64_t raw_ask_size,
        uint8_t size_prec,
        uint64_t ts_event,
        uint64_t ts_init,
    ) -> QuoteTick:
        """
        Return a quote tick from the given raw values.

        Parameters
        ----------
        instrument_id : InstrumentId
            The quotes instrument ID.
        raw_bid : int64_t
            The raw top of book bid price (as a scaled fixed precision integer).
        raw_ask : int64_t
            The raw top of book ask price (as a scaled fixed precision integer).
        price_prec : uint8_t
            The price precision.
        raw_bid_size : Quantity
            The raw top of book bid size (as a scaled fixed precision integer).
        raw_ask_size : Quantity
            The raw top of book ask size (as a scaled fixed precision integer).
        size_prec : uint8_t
            The size precision.
        ts_event: int64
            The UNIX timestamp (nanoseconds) when the tick event occurred.
        ts_init: int64
            The UNIX timestamp (nanoseconds) when the data object was initialized.

        Returns
        -------
        QuoteTick

        """
        return QuoteTick.from_raw_c(
            instrument_id,
            raw_bid,
            raw_ask,
            price_prec,
            raw_bid_size,
            raw_ask_size,
            size_prec,
            ts_event,
            ts_init,
        )

    @staticmethod
    def from_dict(dict values) -> QuoteTick:
        """
        Return a quote tick parsed from the given values.

        Parameters
        ----------
        values : dict[str, object]
            The values for initialization.

        Returns
        -------
        QuoteTick

        """
        return QuoteTick.from_dict_c(values)

    @staticmethod
    def to_dict(QuoteTick obj):
        """
        Return a dictionary representation of this object.

        Returns
        -------
        dict[str, object]

        """
        return QuoteTick.to_dict_c(obj)

    cpdef Price extract_price(self, PriceType price_type):
        """
        Extract the price for the given price type.

        Parameters
        ----------
        price_type : PriceType
            The price type to extract.

        Returns
        -------
        Price

        """
        if price_type == PriceType.MID:
            return Price.from_raw_c(((self._mem.bid.raw + self._mem.ask.raw) / 2), self._mem.bid.precision + 1)
        elif price_type == PriceType.BID:
            return self.bid
        elif price_type == PriceType.ASK:
            return self.ask
        else:
            raise ValueError(f"Cannot extract with PriceType {PriceTypeParser.to_str(price_type)}")

    cpdef Quantity extract_volume(self, PriceType price_type):
        """
        Extract the volume for the given price type.

        Parameters
        ----------
        price_type : PriceType
            The price type to extract.

        Returns
        -------
        Quantity

        """
        if price_type == PriceType.MID:
            return Quantity.from_raw_c((self._mem.bid_size.raw + self._mem.ask_size.raw) / 2, self._mem.bid_size.precision + 1)
        elif price_type == PriceType.BID:
            return self.bid_size
        elif price_type == PriceType.ASK:
            return self.ask_size
        else:
            raise ValueError(f"Cannot extract with PriceType {PriceTypeParser.to_str(price_type)}")


cdef class TradeTick(Data):
    """
    Represents a single trade tick in a financial market.

    Contains information about a single unique trade which matched buyer and
    seller counterparties.

    Parameters
    ----------
    instrument_id : InstrumentId
        The trade instrument ID.
    price : Price
        The traded price.
    size : Quantity
        The traded size.
    aggressor_side : AggressorSide
        The trade aggressor side.
    trade_id : TradeId
        The trade match ID (assigned by the venue).
    ts_event: int64
        The UNIX timestamp (nanoseconds) when the tick event occurred.
    ts_init: int64
        The UNIX timestamp (nanoseconds) when the data object was initialized.

    Raises
    ------
    ValueError
        If `trade_id` is not a valid string.
    """

    def __init__(
        self,
        InstrumentId instrument_id not None,
        Price price not None,
        Quantity size not None,
        AggressorSide aggressor_side,
        TradeId trade_id not None,
        int64_t ts_event,
        int64_t ts_init,
    ):
        super().__init__(ts_event, ts_init)

        self._mem = trade_tick_from_raw(
            instrument_id._mem,
            price._mem.raw,
            price._mem.precision,
            size._mem.raw,
            size._mem.precision,
            <OrderSide>aggressor_side,
            trade_id._mem,
            ts_event,
            ts_init,
        )

    def __del__(self) -> None:
        trade_tick_free(self._mem)  # `self._mem` moved to Rust (then dropped)

    def __eq__(self, TradeTick other) -> bool:
        return TradeTick.to_dict_c(self) == TradeTick.to_dict_c(other)

    def __hash__(self) -> int:
        return hash(frozenset(TradeTick.to_dict_c(self)))

    def __str__(self) -> str:
        return (
            f"{self.instrument_id.value},"
            f"{self.price},"
            f"{self.size},"
            f"{AggressorSideParser.to_str(self._mem.aggressor_side)},"
            f"{self.trade_id.value},"
            f"{self.ts_event}"
        )

    def __repr__(self) -> str:
        return f"{type(self).__name__}({self})"

    @property
    def instrument_id(self) -> InstrumentId:
        """
        The tick instrument ID.

        Returns
        -------
        Price

        """
        return InstrumentId.from_raw_c(self._mem.instrument_id)

    @property
    def trade_id(self) -> InstrumentId:
        """
        The tick instrument ID.

        Returns
        -------
        Price

        """
        return TradeId.from_raw_c(self._mem.trade_id)

    @property
    def price(self) -> Price:
        """
        The ticks price.

        Returns
        -------
        Price

        """
        return Price.from_raw_c(self._mem.price.raw, self._mem.price.precision)

    @property
    def size(self) -> Price:
        """
        The ticks size.

        Returns
        -------
        Quantity

        """
        return Quantity.from_raw_c(self._mem.size.raw, self._mem.size.precision)

    @property
    def aggressor_side(self) -> AggressorSide:
        """
        The ticks aggressor side.

        Returns
        -------
        AggressorSide

        """
        return <AggressorSide>self._mem.aggressor_side

    @staticmethod
    cdef TradeTick from_raw_c(
        InstrumentId instrument_id,
        int64_t raw_price,
        uint8_t price_prec,
        uint64_t raw_size,
        uint8_t size_prec,
        AggressorSide aggressor_side,
        TradeId trade_id,
        uint64_t ts_event,
        uint64_t ts_init,
    ):
        cdef TradeTick tick = TradeTick.__new__(TradeTick)
        tick.ts_event = ts_event
        tick.ts_init = ts_init
        tick._mem = trade_tick_from_raw(
            instrument_id._mem,
            raw_price,
            price_prec,
            raw_size,
            size_prec,
            <OrderSide>aggressor_side,
            trade_id._mem,
            ts_event,
            ts_init,
        )

        return tick

    @staticmethod
    cdef TradeTick from_dict_c(dict values):
        Condition.not_none(values, "values")
        return TradeTick(
            instrument_id=InstrumentId.from_str_c(values["instrument_id"]),
            price=Price.from_str_c(values["price"]),
            size=Quantity.from_str_c(values["size"]),
            aggressor_side=AggressorSideParser.from_str(values["aggressor_side"]),
            trade_id=TradeId(values["trade_id"]),
            ts_event=values["ts_event"],
            ts_init=values["ts_init"],
        )

    @staticmethod
    cdef dict to_dict_c(TradeTick obj):
        Condition.not_none(obj, "obj")
        return {
            "type": type(obj).__name__,
            "instrument_id": obj.instrument_id.value,
            "price": str(obj.price),
            "size": str(obj.size),
            "aggressor_side": AggressorSideParser.to_str(obj._mem.aggressor_side),
            "trade_id": obj.trade_id.value,
            "ts_event": obj.ts_event,
            "ts_init": obj.ts_init,
        }

    @staticmethod
    def from_raw(
        InstrumentId instrument_id,
        int64_t raw_price,
        uint8_t price_prec,
        uint64_t raw_size,
        uint8_t size_prec,
        AggressorSide aggressor_side,
        TradeId trade_id,
        uint64_t ts_event,
        uint64_t ts_init,
    ) -> TradeTick:
        """
        Return a trade tick from the given raw values.

        Parameters
        ----------
        instrument_id : InstrumentId
            The trade instrument ID.
        raw_price : int64_t
            The traded raw price (as a scaled fixed precision integer).
        price_prec : uint8_t
            The traded price precision.
        raw_size : uint64_t
            The traded raw size (as a scaled fixed precision integer).
        size_prec : uint8_t
            The traded size precision.
        aggressor_side : AggressorSide
            The trade aggressor side.
        trade_id : TradeId
            The trade match ID (assigned by the venue).
        ts_event: int64
            The UNIX timestamp (nanoseconds) when the tick event occurred.
        ts_init: int64
            The UNIX timestamp (nanoseconds) when the data object was initialized.

        Returns
        -------
        TradeTick

        """
        return TradeTick.from_raw_c(
            instrument_id,
            raw_price,
            price_prec,
            raw_size,
            size_prec,
            aggressor_side,
            trade_id,
            ts_event,
            ts_init,
        )

    @staticmethod
    def from_dict(dict values) -> TradeTick:
        """
        Return a trade tick from the given dict values.

        Parameters
        ----------
        values : dict[str, object]
            The values for initialization.

        Returns
        -------
        TradeTick

        """
        return TradeTick.from_dict_c(values)

    @staticmethod
    def to_dict(TradeTick obj):
        """
        Return a dictionary representation of this object.

        Returns
        -------
        dict[str, object]

        """
        return TradeTick.to_dict_c(obj)
