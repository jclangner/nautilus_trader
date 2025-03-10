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

from nautilus_trader.adapters.interactive_brokers.config import InteractiveBrokersDataClientConfig
from nautilus_trader.adapters.interactive_brokers.factories import (
    InteractiveBrokersLiveDataClientFactory,
)
from nautilus_trader.config import InstrumentProviderConfig
from nautilus_trader.config import RoutingConfig
from nautilus_trader.config import TradingNodeConfig
from nautilus_trader.examples.strategies.subscribe import SubscribeStrategy
from nautilus_trader.examples.strategies.subscribe import SubscribeStrategyConfig
from nautilus_trader.live.node import TradingNode
from nautilus_trader.model.enums import BookType


# *** THIS IS A TEST STRATEGY WITH NO ALPHA ADVANTAGE WHATSOEVER. ***
# *** IT IS NOT INTENDED TO BE USED TO TRADE LIVE WITH REAL MONEY. ***

# *** THIS INTEGRATION IS STILL UNDER CONSTRUCTION. ***
# *** PLEASE CONSIDER IT TO BE IN AN UNSTABLE BETA PHASE AND EXERCISE CAUTION. ***

# Configure the trading node
config_node = TradingNodeConfig(
    trader_id="TESTER-001",
    log_level="INFO",
    data_clients={
        "IB": InteractiveBrokersDataClientConfig(
            gateway_host="127.0.0.1",
            instrument_provider=InstrumentProviderConfig(
                load_all=True,
                filters=tuple({"secType": "CASH", "pair": "EURUSD"}.items()),
                #     filters=tuple(
                #         {
                #             "secType": "STK",
                #             "symbol": "9988",
                #             "exchange": "SEHK",
                #             "currency": "HKD",
                #             "build_options_chain": True,
                #             "option_kwargs": json.dumps(
                #                 {
                #                     "min_expiry": "20220601",
                #                     "max_expiry": "20220701",
                #                     "min_strike": 90,
                #                     "max_strike": 110,
                #                     "exchange": "SEHK"
                #                 }
                #             ),
                #         }.items()
                #     ),
            ),
            routing=RoutingConfig(venues={"IDEALPRO"}),
        ),
    },
    # exec_clients={
    #     "IB": InteractiveBrokersExecClientConfig(),
    # },
    timeout_connection=90.0,
    timeout_reconciliation=5.0,
    timeout_portfolio=5.0,
    timeout_disconnection=5.0,
    timeout_post_stop=2.0,
)

# Instantiate the node with a configuration
node = TradingNode(config=config_node)

# Configure your strategy
strategy_config = SubscribeStrategyConfig(
    instrument_id="EUR/USD.IDEALPRO",
    book_type=BookType.L2_MBP,
    snapshots=True,
    # trade_ticks=True,
    # quote_ticks=True,
)
# Instantiate your strategy
strategy = SubscribeStrategy(config=strategy_config)

# Add your strategies and modules
node.trader.add_strategy(strategy)

# Register your client factories with the node (can take user defined factories)
node.add_data_client_factory("IB", InteractiveBrokersLiveDataClientFactory)
# node.add_exec_client_factory("IB", InteractiveBrokersLiveExecutionClientFactory)
node.build()

# Stop and dispose of the node with SIGINT/CTRL+C
if __name__ == "__main__":
    try:
        node.start()
    finally:
        node.dispose()
