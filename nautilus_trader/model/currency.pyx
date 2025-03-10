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

from cpython.object cimport PyObject
from libc.stdint cimport uint8_t
from libc.stdint cimport uint16_t

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.rust.model cimport currency_free
from nautilus_trader.core.rust.model cimport currency_from_py
from nautilus_trader.model.c_enums.currency_type cimport CurrencyType
from nautilus_trader.model.c_enums.currency_type cimport CurrencyTypeParser
from nautilus_trader.model.currencies cimport _CURRENCY_MAP


cdef class Currency:
    """
    Represents a medium of exchange in a specified denomination with a fixed
    decimal precision.

    Parameters
    ----------
    code : str
        The currency code.
    precision : uint8
        The currency decimal precision.
    iso4217 : uint16
        The currency ISO 4217 code.
    name : str
        The currency name.
    currency_type : CurrencyType
        The currency type.

    Raises
    ------
    ValueError
        If `code` is not a valid string.
    OverflowError
        If `precision` is negative (< 0).
    ValueError
        If `precision` greater than 9.
    ValueError
        If `name` is not a valid string.
    """

    def __init__(
        self,
        str code,
        uint8_t precision,
        uint16_t iso4217,
        str name,
        CurrencyType currency_type,
    ):
        Condition.valid_string(code, "code")
        Condition.valid_string(name, "name")
        Condition.true(precision <= 9, "invalid precision, was > 9")

        self.code = code
        self.name = name
        self._mem = currency_from_py(
            <PyObject *>code,
            precision,
            iso4217,
            <PyObject *>name,
            currency_type,
        )

    def __del__(self) -> None:
        currency_free(self._mem)  # `self._mem` moved to Rust (then dropped)

    def __getstate__(self):
        return (
            self.code,
            self._mem.precision,
            self._mem.iso4217,
            self.name,
            <CurrencyType>self._mem.currency_type,
        )

    def __setstate__(self, state):
        self.code = state[0]
        self.name = state[3]
        self._mem = currency_from_py(
            <PyObject *>self.code,
            state[1],
            state[2],
            <PyObject *>self.name,
            state[4],
        )

    def __eq__(self, Currency other) -> bool:
        return self.code == other.code and self._mem.precision == other._mem.precision

    def __hash__(self) -> int:
        return hash((self.code, self.precision))

    def __str__(self) -> str:
        return self.code

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"code={self.code}, "
            f"name={self.name}, "
            f"precision={self._mem.precision}, "
            f"iso4217={self._mem.iso4217}, "
            f"type={CurrencyTypeParser.to_str(<CurrencyType>self._mem.currency_type)})"
        )

    @property
    def precision(self) -> int:
        """
        The currency decimal precision.

        Returns
        -------
        uint8

        """
        return self._mem.precision

    @property
    def iso4217(self) -> int:
        """
        The currency ISO 4217 code.

        Returns
        -------
        str

        """
        return self._mem.iso4217

    @property
    def currency_type(self) -> CurrencyType:
        """
        The currency type.

        Returns
        -------
        CurrencyType

        """
        return <CurrencyType>self._mem.currency_type

    cdef uint8_t get_precision(self):
        return self._mem.precision

    @staticmethod
    cdef void register_c(Currency currency, bint overwrite=False) except *:
        if not overwrite and currency.code in _CURRENCY_MAP:
            return
        _CURRENCY_MAP[currency.code] = currency

    @staticmethod
    cdef Currency from_str_c(str code, bint strict=False):
        cdef Currency currency = _CURRENCY_MAP.get(code)
        if strict or currency is not None:
            return currency

        # Strict mode false with no currency found (very likely a crypto)
        currency = Currency(
            code=code,
            precision=8,
            iso4217=0,
            name=code,
            currency_type=CurrencyType.CRYPTO,
        )
        print(f"Currency '{code}' not found, created {repr(currency)}")
        return currency

    @staticmethod
    def register(Currency currency, bint overwrite=False):
        """
        Register the given currency.

        Will override the internal currency map.

        Parameters
        ----------
        currency : Currency
            The currency to register
        overwrite : bool
            If the currency in the internal currency map should be overwritten.

        """
        Condition.not_none(currency, "currency")

        return Currency.register_c(currency, overwrite)

    @staticmethod
    def from_str(str code, bint strict=False):
        """
        Parse a currency from the given string (if found).

        Parameters
        ----------
        code : str
            The code of the currency to get.
        strict : bool, default False
            If strict mode is enabled. If not strict mode then it's very likely
            the currency is a crypto, so for robustness will then return a new
            cryptocurrency using the code and a default precision of 8.

        Returns
        -------
        Currency or ``None``

        """
        return Currency.from_str_c(code, strict)

    @staticmethod
    cdef bint is_fiat_c(str code):
        cdef Currency currency = _CURRENCY_MAP.get(code)
        if currency is None:
            return False

        return <CurrencyType>currency._mem.currency_type == CurrencyType.FIAT

    @staticmethod
    cdef bint is_crypto_c(str code):
        cdef Currency currency = _CURRENCY_MAP.get(code)
        if currency is None:
            return False

        return <CurrencyType>currency._mem.currency_type == CurrencyType.CRYPTO

    @staticmethod
    def is_fiat(str code):
        """
        Return a value indicating whether a currency with the given code is ``FIAT``.

        Parameters
        ----------
        code : str
            The code of the currency.

        Returns
        -------
        bool
            True if ``FIAT``, else False.

        Raises
        ------
        ValueError
            If `code` is not a valid string.

        """
        Condition.valid_string(code, "code")

        return Currency.is_fiat_c(code)

    @staticmethod
    def is_crypto(str code):
        """
        Return a value indicating whether a currency with the given code is ``CRYPTO``.

        Parameters
        ----------
        code : str
            The code of the currency.

        Returns
        -------
        bool
            True if ``CRYPTO``, else False.

        Raises
        ------
        ValueError
            If `code` is not a valid string.

        """
        Condition.valid_string(code, "code")

        return Currency.is_crypto_c(code)
