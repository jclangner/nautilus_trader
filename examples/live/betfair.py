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

import asyncio
import traceback

from nautilus_trader.adapters.betfair.factories import BetfairLiveDataClientFactory
from nautilus_trader.adapters.betfair.factories import BetfairLiveExecClientFactory
from nautilus_trader.adapters.betfair.factories import get_cached_betfair_client
from nautilus_trader.adapters.betfair.factories import get_cached_betfair_instrument_provider
from nautilus_trader.common.clock import LiveClock
from nautilus_trader.common.logging import LiveLogger
from nautilus_trader.config import CacheDatabaseConfig
from nautilus_trader.config import TradingNodeConfig
from nautilus_trader.examples.strategies.orderbook_imbalance import OrderBookImbalance
from nautilus_trader.examples.strategies.orderbook_imbalance import OrderBookImbalanceConfig
from nautilus_trader.live.node import TradingNode


# *** THIS IS A TEST STRATEGY WITH NO ALPHA ADVANTAGE WHATSOEVER. ***
# *** IT IS NOT INTENDED TO BE USED TO TRADE LIVE WITH REAL MONEY. ***


async def main(market_id: str):
    # Connect to Betfair client early to load instruments and account currency
    loop = asyncio.get_event_loop()
    logger = LiveLogger(loop=loop, clock=LiveClock())
    client = get_cached_betfair_client(
        username=None,  # Pass here or will source from the `BETFAIR_USERNAME` env var
        password=None,  # Pass here or will source from the `BETFAIR_PASSWORD` env var
        app_key=None,  # Pass here or will source from the `BETFAIR_APP_KEY` env var
        cert_dir=None,  # Pass here or will source from the `BETFAIR_CERT_DIR` env var
        logger=logger,
        loop=loop,
    )
    await client.connect()

    # Find instruments for a particular market_id
    market_filter = {"market_id": (market_id,)}
    provider = get_cached_betfair_instrument_provider(
        client=client,
        logger=logger,
        market_filter=tuple(market_filter.items()),
    )
    await provider.load_all_async()
    instruments = provider.list_all()
    print(f"Found instruments:\n{instruments}")

    # Determine account currency
    account = await client.get_account_details()

    # Configure trading node
    config = TradingNodeConfig(
        timeout_connection=30.0,
        log_level="DEBUG",
        cache_database=CacheDatabaseConfig(type="in-memory"),
        exec_engine={"allow_cash_positions": True},  # Retain original behaviour for now
        data_clients={
            "BETFAIR": {
                # "username": "YOUR_BETFAIR_USERNAME",
                # "password": "YOUR_BETFAIR_PASSWORD",
                # "app_key": "YOUR_BETFAIR_APP_KEY",
                # "cert_dir": "YOUR_BETFAIR_CERT_DIR",
                "market_filter": market_filter,
            },
        },
        exec_clients={
            "BETFAIR": {
                "base_currency": account["currencyCode"],
                # "username": "YOUR_BETFAIR_USERNAME",
                # "password": "YOUR_BETFAIR_PASSWORD",
                # "app_key": "YOUR_BETFAIR_APP_KEY",
                # "cert_dir": "YOUR_BETFAIR_CERT_DIR",
                "market_filter": market_filter,
            },
        },
    )
    strategies = [
        OrderBookImbalance(
            config=OrderBookImbalanceConfig(
                instrument_id=instrument.id.value,
                max_trade_size=10,
                order_id_tag=instrument.selection_id,
            )
        )
        for instrument in instruments
    ]

    # Setup TradingNode
    node = TradingNode(config=config)
    node.trader.add_strategies(strategies)

    # Register your client factories with the node (can take user defined factories)
    node.add_data_client_factory("BETFAIR", BetfairLiveDataClientFactory)
    node.add_exec_client_factory("BETFAIR", BetfairLiveExecClientFactory)
    node.build()

    try:
        node.start()
    except Exception as ex:
        print(ex)
        print(traceback.format_exc())
    finally:
        node.dispose()


if __name__ == "__main__":
    # Update the market ID with something coming up in `Next Races` from
    # https://www.betfair.com.au/exchange/plus/
    # The market ID will appear in the browser query string.
    asyncio.run(main(market_id="1.190036127"))
