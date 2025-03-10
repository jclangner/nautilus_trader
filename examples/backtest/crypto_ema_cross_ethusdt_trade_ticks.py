#!/usr/bin/env python3
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

import pandas as pd

from nautilus_trader.backtest.data.providers import TestDataProvider
from nautilus_trader.backtest.data.providers import TestInstrumentProvider
from nautilus_trader.backtest.data.wranglers import TradeTickDataWrangler
from nautilus_trader.backtest.engine import BacktestEngine
from nautilus_trader.backtest.engine import BacktestEngineConfig
from nautilus_trader.backtest.models import FillModel
from nautilus_trader.examples.strategies.ema_cross import EMACross
from nautilus_trader.examples.strategies.ema_cross import EMACrossConfig
from nautilus_trader.model.currencies import ETH
from nautilus_trader.model.currencies import USDT
from nautilus_trader.model.enums import AccountType
from nautilus_trader.model.enums import OMSType
from nautilus_trader.model.identifiers import InstrumentId
from nautilus_trader.model.identifiers import Symbol
from nautilus_trader.model.identifiers import Venue
from nautilus_trader.model.objects import Money


if __name__ == "__main__":
    # Configure backtest engine
    config = BacktestEngineConfig(
        trader_id="BACKTESTER-001",
        exec_engine={"allow_cash_positions": True},  # Retain original behaviour for now
    )
    # Build the backtest engine
    engine = BacktestEngine(config=config)

    BINANCE = Venue("BINANCE")
    instrument_id = InstrumentId(symbol=Symbol("ETHUSDT"), venue=BINANCE)
    ETHUSDT_BINANCE = TestInstrumentProvider.ethusdt_binance()

    # Setup data
    provider = TestDataProvider()
    wrangler = TradeTickDataWrangler(instrument=ETHUSDT_BINANCE)
    ticks = wrangler.process(provider.read_csv_ticks("binance-ethusdt-trades.csv"))
    engine.add_instrument(ETHUSDT_BINANCE)
    engine.add_data(ticks)

    # Create a fill model (optional)
    fill_model = FillModel(
        prob_fill_on_limit=0.2,
        prob_fill_on_stop=0.95,
        prob_slippage=0.5,
        random_seed=42,
    )

    # Add an exchange (multiple exchanges possible)
    # Add starting balances for single-currency or multi-currency accounts
    engine.add_venue(
        venue=BINANCE,
        oms_type=OMSType.NETTING,
        account_type=AccountType.CASH,  # Spot cash account
        base_currency=None,  # Multi-currency account
        starting_balances=[Money(1_000_000, USDT), Money(10, ETH)],
        fill_model=fill_model,
    )

    # Configure your strategy
    config = EMACrossConfig(
        instrument_id=str(ETHUSDT_BINANCE.id),
        bar_type="ETHUSDT.BINANCE-250-TICK-LAST-INTERNAL",
        trade_size=Decimal("0.05"),
        fast_ema=10,
        slow_ema=20,
        order_id_tag="001",
    )
    # Instantiate and add your strategy
    strategy = EMACross(config=config)
    engine.add_strategy(strategy=strategy)

    input("Press Enter to continue...")  # noqa (always Python 3)

    # Run the engine (from start to end of data)
    engine.run()

    # Optionally view reports
    with pd.option_context(
        "display.max_rows",
        100,
        "display.max_columns",
        None,
        "display.width",
        300,
    ):
        print(engine.trader.generate_account_report(BINANCE))
        print(engine.trader.generate_order_fills_report())
        print(engine.trader.generate_positions_report())

    # For repeated backtest runs make sure to reset the engine
    engine.reset()

    # Good practice to dispose of the object
    engine.dispose()
