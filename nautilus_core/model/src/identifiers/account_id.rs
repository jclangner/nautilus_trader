// -------------------------------------------------------------------------------------------------
//  Copyright (C) 2015-2022 Nautech Systems Pty Ltd. All rights reserved.
//  https://nautechsystems.io
//
//  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
//  You may not use this file except in compliance with the License.
//  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// -------------------------------------------------------------------------------------------------

use nautilus_core::string::{pystr_to_string, string_to_pystr};
use pyo3::ffi;
use std::fmt::{Debug, Display, Formatter, Result};

#[repr(C)]
#[derive(Clone, Hash, PartialEq, Debug)]
#[allow(clippy::box_collection)] // C ABI compatibility
pub struct AccountId {
    value: Box<String>,
}

impl From<&str> for AccountId {
    fn from(s: &str) -> AccountId {
        AccountId {
            value: Box::new(s.to_string()),
        }
    }
}

impl Display for AccountId {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result {
        write!(f, "{}", self.value)
    }
}

////////////////////////////////////////////////////////////////////////////////
// C API
////////////////////////////////////////////////////////////////////////////////
#[no_mangle]
pub extern "C" fn account_id_free(account_id: AccountId) {
    drop(account_id); // Memory freed here
}

/// Returns a Nautilus identifier from a valid Python object pointer.
///
/// # Safety
///
/// - `ptr` must be borrowed from a valid Python UTF-8 `str`.
#[no_mangle]
pub unsafe extern "C" fn account_id_from_pystr(ptr: *mut ffi::PyObject) -> AccountId {
    AccountId {
        value: Box::new(pystr_to_string(ptr)),
    }
}

/// Returns a pointer to a valid Python UTF-8 string.
///
/// # Safety
///
/// - Assumes that since the data is originating from Rust, the GIL does not need
/// to be acquired.
/// - Assumes you are immediately returning this pointer to Python.
#[no_mangle]
pub unsafe extern "C" fn account_id_to_pystr(account_id: &AccountId) -> *mut ffi::PyObject {
    string_to_pystr(account_id.value.as_str())
}

////////////////////////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::AccountId;
    use crate::identifiers::account_id::{account_id_from_pystr, account_id_to_pystr};
    use nautilus_core::string::pystr_to_string;
    use pyo3::types::PyString;
    use pyo3::{prepare_freethreaded_python, IntoPyPointer, Python};

    #[test]
    fn test_account_id_from_str() {
        let account_id1 = AccountId::from("123456789");
        let account_id2 = AccountId::from("234567890");

        assert_eq!(account_id1, account_id1);
        assert_ne!(account_id1, account_id2);
    }

    #[test]
    fn test_account_id_as_str() {
        let account_id = AccountId::from("1234567890");

        assert_eq!(account_id.to_string(), "1234567890");
    }

    #[test]
    fn test_account_id_from_pystr() {
        prepare_freethreaded_python();
        let gil = Python::acquire_gil();
        let py = gil.python();
        let pystr = PyString::new(py, "SIM-02851908").into_ptr();

        let uuid = unsafe { account_id_from_pystr(pystr) };

        assert_eq!(uuid.to_string(), "SIM-02851908")
    }

    #[test]
    fn test_account_id_to_pystr() {
        prepare_freethreaded_python();
        let gil = Python::acquire_gil();
        let _py = gil.python();
        let account_id = AccountId::from("SIM-02851908");
        let ptr = unsafe { account_id_to_pystr(&account_id) };

        let s = unsafe { pystr_to_string(ptr) };
        assert_eq!(s, "SIM-02851908")
    }
}
