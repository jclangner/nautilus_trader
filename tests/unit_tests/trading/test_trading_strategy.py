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

from datetime import datetime
from datetime import timedelta
from decimal import Decimal

import pytest
import pytz

from nautilus_trader.backtest.data.providers import TestInstrumentProvider
from nautilus_trader.backtest.data_client import BacktestMarketDataClient
from nautilus_trader.backtest.exchange import SimulatedExchange
from nautilus_trader.backtest.execution_client import BacktestExecClient
from nautilus_trader.backtest.models import FillModel
from nautilus_trader.backtest.models import LatencyModel
from nautilus_trader.common.clock import TestClock
from nautilus_trader.common.enums import ComponentState
from nautilus_trader.common.enums import LogLevel
from nautilus_trader.common.logging import Logger
from nautilus_trader.common.uuid import UUIDFactory
from nautilus_trader.config import StrategyConfig
from nautilus_trader.data.engine import DataEngine
from nautilus_trader.execution.engine import ExecutionEngine
from nautilus_trader.indicators.average.ema import ExponentialMovingAverage
from nautilus_trader.model.currencies import USD
from nautilus_trader.model.data.bar import Bar
from nautilus_trader.model.enums import AccountType
from nautilus_trader.model.enums import OMSType
from nautilus_trader.model.enums import OrderSide
from nautilus_trader.model.enums import OrderStatus
from nautilus_trader.model.enums import PriceType
from nautilus_trader.model.identifiers import ClientId
from nautilus_trader.model.identifiers import PositionId
from nautilus_trader.model.identifiers import StrategyId
from nautilus_trader.model.identifiers import Venue
from nautilus_trader.model.objects import Money
from nautilus_trader.model.objects import Price
from nautilus_trader.model.objects import Quantity
from nautilus_trader.msgbus.bus import MessageBus
from nautilus_trader.portfolio.portfolio import Portfolio
from nautilus_trader.risk.engine import RiskEngine
from nautilus_trader.trading.strategy import Strategy
from tests.test_kit.mocks.strategies import KaboomStrategy
from tests.test_kit.mocks.strategies import MockStrategy
from tests.test_kit.stubs.component import TestComponentStubs
from tests.test_kit.stubs.data import TestDataStubs
from tests.test_kit.stubs.events import TestEventStubs
from tests.test_kit.stubs.identifiers import TestIdStubs


AUDUSD_SIM = TestInstrumentProvider.default_fx_ccy("AUD/USD")
GBPUSD_SIM = TestInstrumentProvider.default_fx_ccy("GBP/USD")
USDJPY_SIM = TestInstrumentProvider.default_fx_ccy("USD/JPY")


class TestStrategy:
    def setup(self):
        # Fixture Setup
        self.clock = TestClock()
        self.uuid_factory = UUIDFactory()
        self.logger = Logger(
            clock=self.clock,
            level_stdout=LogLevel.DEBUG,
        )

        self.trader_id = TestIdStubs.trader_id()

        self.msgbus = MessageBus(
            trader_id=self.trader_id,
            clock=self.clock,
            logger=self.logger,
        )

        self.cache = TestComponentStubs.cache()

        self.portfolio = Portfolio(
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        self.data_engine = DataEngine(
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        self.exec_engine = ExecutionEngine(
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        self.risk_engine = RiskEngine(
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        self.exchange = SimulatedExchange(
            venue=Venue("SIM"),
            oms_type=OMSType.HEDGING,
            account_type=AccountType.MARGIN,
            base_currency=USD,
            starting_balances=[Money(1_000_000, USD)],
            default_leverage=Decimal(50),
            leverages={},
            is_frozen_account=False,
            cache=self.cache,
            instruments=[USDJPY_SIM],
            modules=[],
            fill_model=FillModel(),
            clock=self.clock,
            logger=self.logger,
            latency_model=LatencyModel(0),
        )

        self.data_client = BacktestMarketDataClient(
            client_id=ClientId("SIM"),
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        self.exec_client = BacktestExecClient(
            exchange=self.exchange,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        # Wire up components
        self.exchange.register_client(self.exec_client)
        self.data_engine.register_client(self.data_client)
        self.exec_engine.register_client(self.exec_client)
        self.exchange.reset()

        # Add instruments
        self.data_engine.process(AUDUSD_SIM)
        self.data_engine.process(GBPUSD_SIM)
        self.data_engine.process(USDJPY_SIM)
        self.cache.add_instrument(AUDUSD_SIM)
        self.cache.add_instrument(GBPUSD_SIM)
        self.cache.add_instrument(USDJPY_SIM)

        self.exchange.process_quote_tick(
            TestDataStubs.quote_tick_3decimal(USDJPY_SIM.id)
        )  # Prepare market

        self.data_engine.start()
        self.exec_engine.start()

    def test_strategy_equality(self):
        # Arrange
        strategy1 = Strategy(config=StrategyConfig(order_id_tag="AUD/USD-001"))
        strategy2 = Strategy(config=StrategyConfig(order_id_tag="AUD/USD-001"))
        strategy3 = Strategy(config=StrategyConfig(order_id_tag="AUD/USD-002"))

        # Act, Assert
        assert strategy1 == strategy1
        assert strategy1 == strategy2
        assert strategy2 != strategy3

    def test_str_and_repr(self):
        # Arrange
        strategy = Strategy(config=StrategyConfig(order_id_tag="GBP/USD-MM"))

        # Act, Assert
        assert str(strategy) == "Strategy-GBP/USD-MM"
        assert repr(strategy) == "Strategy(Strategy-GBP/USD-MM)"

    def test_id(self):
        # Arrange
        strategy = Strategy()

        # Act, Assert
        assert strategy.id == StrategyId("Strategy-000")

    def test_initialization(self):
        # Arrange
        strategy = Strategy(config=StrategyConfig(order_id_tag="001"))

        # Act, Assert
        assert strategy.state == ComponentState.PRE_INITIALIZED
        assert not strategy.indicators_initialized()

    def test_on_save_when_not_overridden_does_nothing(self):
        # Arrange
        strategy = Strategy()

        # Act
        strategy.on_save()

        # Assert
        assert True  # Exception not raised

    def test_on_load_when_not_overridden_does_nothing(self):
        # Arrange
        strategy = Strategy()

        # Act
        strategy.on_load({})

        # Assert
        assert True  # Exception not raised

    def test_save_when_not_registered_logs_error(self):
        # Arrange
        config = StrategyConfig()

        strategy = Strategy(config)
        strategy.save()

        # Assert
        assert True  # Exception not raised

    def test_save_when_user_code_raises_error_logs_and_reraises(self):
        # Arrange
        strategy = KaboomStrategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        # Act, Assert
        with pytest.raises(RuntimeError):
            strategy.save()

    def test_load_when_user_code_raises_error_logs_and_reraises(self):
        # Arrange
        strategy = KaboomStrategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        # Act, Assert
        with pytest.raises(RuntimeError):
            strategy.load({"something": b"123456"})

    def test_load(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        state = {}

        # Act
        strategy.load(state)

        # Assert
        # TODO: Write a users custom save method
        assert True

    def test_reset(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = MockStrategy(bar_type)
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        bar = Bar(
            bar_type,
            Price.from_str("1.00001"),
            Price.from_str("1.00004"),
            Price.from_str("1.00002"),
            Price.from_str("1.00003"),
            Quantity.from_int(100000),
            0,
            0,
        )

        strategy.handle_bar(bar)

        # Act
        strategy.reset()

        # Assert
        assert "on_reset" in strategy.calls
        assert strategy.is_initialized
        assert strategy.ema1.count == 0
        assert strategy.ema2.count == 0

    def test_dispose(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = MockStrategy(bar_type)
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        strategy.reset()

        # Act
        strategy.dispose()

        # Assert
        assert "on_dispose" in strategy.calls
        assert strategy.is_disposed

    def test_save_load(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = MockStrategy(bar_type)
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        # Act
        state = strategy.save()
        strategy.load(state)

        # Assert
        assert state == {"UserState": b"1"}
        assert "on_save" in strategy.calls
        assert strategy.is_initialized

    def test_register_indicator_for_quote_ticks_when_already_registered(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema1 = ExponentialMovingAverage(10, price_type=PriceType.MID)
        ema2 = ExponentialMovingAverage(10, price_type=PriceType.MID)

        # Act
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema1)
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema2)
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema2)

        assert len(strategy.registered_indicators) == 2
        assert ema1 in strategy.registered_indicators
        assert ema2 in strategy.registered_indicators

    def test_register_indicator_for_trade_ticks_when_already_registered(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema1 = ExponentialMovingAverage(10)
        ema2 = ExponentialMovingAverage(10)

        # Act
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema1)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema2)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema2)

        assert len(strategy.registered_indicators) == 2
        assert ema1 in strategy.registered_indicators
        assert ema2 in strategy.registered_indicators

    def test_register_indicator_for_bars_when_already_registered(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema1 = ExponentialMovingAverage(10)
        ema2 = ExponentialMovingAverage(10)
        bar_type = TestDataStubs.bartype_audusd_1min_bid()

        # Act
        strategy.register_indicator_for_bars(bar_type, ema1)
        strategy.register_indicator_for_bars(bar_type, ema2)
        strategy.register_indicator_for_bars(bar_type, ema2)

        assert len(strategy.registered_indicators) == 2
        assert ema1 in strategy.registered_indicators
        assert ema2 in strategy.registered_indicators

    def test_register_indicator_for_multiple_data_sources(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        bar_type = TestDataStubs.bartype_audusd_1min_bid()

        # Act
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema)
        strategy.register_indicator_for_quote_ticks(GBPUSD_SIM.id, ema)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema)
        strategy.register_indicator_for_bars(bar_type, ema)

        assert len(strategy.registered_indicators) == 1
        assert ema in strategy.registered_indicators

    def test_handle_quote_tick_updates_indicator_registered_for_quote_ticks(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10, price_type=PriceType.MID)
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema)

        tick = TestDataStubs.quote_tick_5decimal(AUDUSD_SIM.id)

        # Act
        strategy.handle_quote_tick(tick)
        strategy.handle_quote_tick(tick, True)

        # Assert
        assert ema.count == 2

    def test_handle_quote_ticks_with_no_ticks_logs_and_continues(self):
        # Arrange
        strategy = KaboomStrategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10, price_type=PriceType.MID)
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema)

        # Act
        strategy.handle_quote_ticks([])

        # Assert
        assert ema.count == 0

    def test_handle_quote_ticks_updates_indicator_registered_for_quote_ticks(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10, price_type=PriceType.MID)
        strategy.register_indicator_for_quote_ticks(AUDUSD_SIM.id, ema)

        tick = TestDataStubs.quote_tick_5decimal(AUDUSD_SIM.id)

        # Act
        strategy.handle_quote_ticks([tick])

        # Assert
        assert ema.count == 1

    def test_handle_trade_tick_updates_indicator_registered_for_trade_ticks(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema)

        tick = TestDataStubs.trade_tick_5decimal(AUDUSD_SIM.id)

        # Act
        strategy.handle_trade_tick(tick)
        strategy.handle_trade_tick(tick, True)

        # Assert
        assert ema.count == 2

    def test_handle_trade_ticks_updates_indicator_registered_for_trade_ticks(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema)

        tick = TestDataStubs.trade_tick_5decimal(AUDUSD_SIM.id)

        # Act
        strategy.handle_trade_ticks([tick])

        # Assert
        assert ema.count == 1

    def test_handle_trade_ticks_with_no_ticks_logs_and_continues(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_trade_ticks(AUDUSD_SIM.id, ema)

        # Act
        strategy.handle_trade_ticks([])

        # Assert
        assert ema.count == 0

    def test_handle_bar_updates_indicator_registered_for_bars(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_bars(bar_type, ema)
        bar = TestDataStubs.bar_5decimal()

        # Act
        strategy.handle_bar(bar)
        strategy.handle_bar(bar, True)

        # Assert
        assert ema.count == 2

    def test_handle_bars_updates_indicator_registered_for_bars(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_bars(bar_type, ema)
        bar = TestDataStubs.bar_5decimal()

        # Act
        strategy.handle_bars([bar])

        # Assert
        assert ema.count == 1

    def test_handle_bars_with_no_bars_logs_and_continues(self):
        # Arrange
        bar_type = TestDataStubs.bartype_gbpusd_1sec_mid()
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        ema = ExponentialMovingAverage(10)
        strategy.register_indicator_for_bars(bar_type, ema)

        # Act
        strategy.handle_bars([])

        # Assert
        assert ema.count == 0

    def test_stop_cancels_a_running_time_alert(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = MockStrategy(bar_type)
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        alert_time = datetime.now(pytz.utc) + timedelta(milliseconds=200)
        strategy.clock.set_time_alert("test_alert1", alert_time)

        # Act
        strategy.start()
        strategy.stop()

        # Assert
        assert len(strategy.clock.timer_names()) == 0

    def test_stop_cancels_a_running_timer(self):
        # Arrange
        bar_type = TestDataStubs.bartype_audusd_1min_bid()
        strategy = MockStrategy(bar_type)
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        start_time = datetime.now(pytz.utc) + timedelta(milliseconds=100)
        strategy.clock.set_timer(
            "test_timer", timedelta(milliseconds=100), start_time, stop_time=None
        )

        # Act
        strategy.start()
        strategy.stop()

        # Assert
        assert len(strategy.clock.timer_names()) == 0

    def test_submit_order_with_valid_order_successfully_submits(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
        )

        # Act
        strategy.submit_order(order)
        self.exchange.process(0)

        # Assert
        assert order in strategy.cache.orders()
        assert strategy.cache.orders()[0].status == OrderStatus.FILLED
        assert order.client_order_id not in strategy.cache.orders_open()
        assert not strategy.cache.is_order_open(order.client_order_id)
        assert strategy.cache.is_order_closed(order.client_order_id)

    def test_submit_order_list_with_valid_order_successfully_submits(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        bracket = strategy.order_factory.bracket_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            stop_loss=Price.from_str("90.000"),
            take_profit=Price.from_str("90.500"),
        )

        # Act
        strategy.submit_order_list(bracket)

        # Assert
        assert bracket.orders[0] in strategy.cache.orders()
        assert bracket.orders[1] in strategy.cache.orders()
        assert bracket.orders[2] in strategy.cache.orders()
        # TODO: Implement
        # assert bracket.orders[0].status == OrderStatus.ACCEPTED
        # assert entry in strategy.cache.orders_open()
        # assert strategy.cache.is_order_open(entry.client_order_id)
        # assert not strategy.cache.is_order_closed(entry.client_order_id)

    def test_cancel_order(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.stop_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.006"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)

        # Act
        strategy.cancel_order(order)
        self.exchange.process(0)

        # Assert
        assert order in strategy.cache.orders()
        assert strategy.cache.orders()[0].status == OrderStatus.CANCELED
        assert order.client_order_id == strategy.cache.orders_closed()[0].client_order_id
        assert order not in strategy.cache.orders_open()
        assert strategy.cache.order_exists(order.client_order_id)
        assert not strategy.cache.is_order_open(order.client_order_id)
        assert strategy.cache.is_order_closed(order.client_order_id)

    def test_cancel_order_when_pending_cancel_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.stop_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.006"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)
        self.exec_engine.process(TestEventStubs.order_pending_cancel(order))

        # Act
        strategy.cancel_order(order)
        self.exchange.process(0)

        # Assert
        assert strategy.cache.orders()[0].status == OrderStatus.PENDING_CANCEL
        assert order in strategy.cache.orders_open()
        assert strategy.cache.order_exists(order.client_order_id)
        assert strategy.cache.is_order_open(order.client_order_id)
        assert not strategy.cache.is_order_closed(order.client_order_id)

    def test_cancel_order_when_closed_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.stop_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.006"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)
        self.exec_engine.process(TestEventStubs.order_expired(order))

        # Act
        strategy.cancel_order(order)
        self.exchange.process(0)

        # Assert
        assert strategy.cache.orders()[0].status == OrderStatus.EXPIRED
        assert order not in strategy.cache.orders_open()
        assert strategy.cache.order_exists(order.client_order_id)
        assert not strategy.cache.is_order_open(order.client_order_id)
        assert strategy.cache.is_order_closed(order.client_order_id)

    def test_modify_order_when_pending_update_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.limit(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.001"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)
        self.exec_engine.process(TestEventStubs.order_pending_update(order))

        # Act
        strategy.modify_order(
            order=order,
            quantity=Quantity.from_int(100000),
            price=Price.from_str("90.000"),
        )
        self.exchange.process(0)

        # Assert
        assert self.exec_engine.command_count == 1

    def test_modify_order_when_pending_cancel_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.limit(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.001"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)
        self.exec_engine.process(TestEventStubs.order_pending_cancel(order))

        # Act
        strategy.modify_order(
            order=order,
            quantity=Quantity.from_int(100000),
            price=Price.from_str("90.000"),
        )
        self.exchange.process(0)

        # Assert
        assert self.exec_engine.command_count == 1

    def test_modify_order_when_closed_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.limit(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.001"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)
        self.exec_engine.process(TestEventStubs.order_expired(order))

        # Act
        strategy.modify_order(
            order=order,
            quantity=Quantity.from_int(100000),
            price=Price.from_str("90.000"),
        )
        self.exchange.process(0)

        # Assert
        assert self.exec_engine.command_count == 1

    def test_modify_order_when_no_changes_does_not_submit_command(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.limit(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.001"),
        )

        strategy.submit_order(order)

        # Act
        strategy.modify_order(
            order=order,
            quantity=Quantity.from_int(100000),
            price=Price.from_str("90.001"),
        )

        # Assert
        assert self.exec_engine.command_count == 1

    def test_modify_order(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.limit(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.000"),
        )

        strategy.submit_order(order)
        self.exchange.process(0)

        # Act
        strategy.modify_order(
            order=order,
            quantity=Quantity.from_int(110000),
            price=Price.from_str("90.001"),
        )
        self.exchange.process(0)

        # Assert
        assert strategy.cache.orders()[0] == order
        assert strategy.cache.orders()[0].status == OrderStatus.ACCEPTED
        assert strategy.cache.orders()[0].quantity == Quantity.from_int(110000)
        assert strategy.cache.orders()[0].price == Price.from_str("90.001")
        assert strategy.cache.order_exists(order.client_order_id)
        assert strategy.cache.is_order_open(order.client_order_id)
        assert not strategy.cache.is_order_closed(order.client_order_id)
        assert strategy.portfolio.is_flat(order.instrument_id)

    def test_cancel_all_orders(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order1 = strategy.order_factory.stop_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.007"),
        )

        order2 = strategy.order_factory.stop_market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
            Price.from_str("90.006"),
        )

        strategy.submit_order(order1)
        self.exchange.process(0)
        strategy.submit_order(order2)
        self.exchange.process(0)

        # Act
        strategy.cancel_all_orders(USDJPY_SIM.id)
        self.exchange.process(0)

        # Assert
        assert order1 in self.cache.orders()
        assert order2 in self.cache.orders()
        assert self.cache.orders()[0].status == OrderStatus.CANCELED
        assert self.cache.orders()[1].status == OrderStatus.CANCELED
        assert order1 in self.cache.orders_closed()
        assert order2 in strategy.cache.orders_closed()

    def test_close_position_when_position_already_closed_does_nothing(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order1 = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
        )

        order2 = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.SELL,
            Quantity.from_int(100000),
        )

        strategy.submit_order(order1)
        self.exchange.process(0)
        strategy.submit_order(order2, PositionId("SIM-1-001"))  # Generated by exchange
        self.exchange.process(0)

        position = strategy.cache.positions_closed()[0]

        # Act
        strategy.close_position(position)
        self.exchange.process(0)

        # Assert
        assert strategy.portfolio.is_completely_flat()

    def test_close_position(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        order = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
        )

        strategy.submit_order(order)
        self.exchange.process(0)

        position = self.cache.positions_open()[0]

        # Act
        strategy.close_position(position, tags="EXIT")
        self.exchange.process(0)

        # Assert
        assert order.status == OrderStatus.FILLED
        assert strategy.portfolio.is_completely_flat()
        orders = self.cache.orders(instrument_id=USDJPY_SIM.id)
        for order in orders:
            if order.side == OrderSide.SELL:
                assert order.tags == "EXIT"

    def test_close_all_positions(self):
        # Arrange
        strategy = Strategy()
        strategy.register(
            trader_id=self.trader_id,
            portfolio=self.portfolio,
            msgbus=self.msgbus,
            cache=self.cache,
            clock=self.clock,
            logger=self.logger,
        )

        # Start strategy and submit orders to open positions
        strategy.start()

        order1 = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
        )

        order2 = strategy.order_factory.market(
            USDJPY_SIM.id,
            OrderSide.BUY,
            Quantity.from_int(100000),
        )

        strategy.submit_order(order1)
        self.exchange.process(0)
        strategy.submit_order(order2)
        self.exchange.process(0)

        # Act
        strategy.close_all_positions(USDJPY_SIM.id, tags="EXIT")
        self.exchange.process(0)

        # Assert
        assert order1.status == OrderStatus.FILLED
        assert order2.status == OrderStatus.FILLED
        assert strategy.portfolio.is_completely_flat()
        orders = self.cache.orders(instrument_id=USDJPY_SIM.id)
        for order in orders:
            if order.side == OrderSide.SELL:
                assert order.tags == "EXIT"
