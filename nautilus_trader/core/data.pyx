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


cdef class Data:
    """
    The abstract base class for all data.

    Parameters
    ----------
    ts_event : int64
        The UNIX timestamp (nanoseconds) when the data event occurred.
    ts_init : int64
        The UNIX timestamp (nanoseconds) when the object was initialized.

    Warnings
    --------
    This class should not be used directly, but through a concrete subclass.
    """

    def __init__(self, int64_t ts_event, int64_t ts_init):
        # Design-time invariant: correct ordering of timestamps
        assert ts_event <= ts_init

        self.ts_event = ts_event
        self.ts_init = ts_init

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"ts_event={self.ts_event}, "
            f"ts_init={self.ts_init})"
        )

    @classmethod
    def fully_qualified_name(cls) -> str:
        """
        Return the fully qualified name for the `Data` class.

        Returns
        -------
        str

        References
        ----------
        https://www.python.org/dev/peps/pep-3155/

        """
        return cls.__module__ + ':' + cls.__qualname__
