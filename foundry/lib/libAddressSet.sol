// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
    mapping(address => bool) blacklisted;
}

library LibAddressSet {
    function add(AddressSet storage set, address addr) internal {
        if ((!set.saved[addr]) && (!set.blacklisted[addr])) {
            set.addrs.push(addr);
            set.saved[addr] = true;
        }
    }

    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return set.addrs[index];
    }

    function blackList(AddressSet storage set, address addr) external {
        set.blacklisted[addr] = true;
    }

    function contains(AddressSet storage set, address addr) internal view returns (bool) {
        return set.saved[addr];
    }

    function count(AddressSet storage set) internal view returns (uint256) {
        return set.addrs.length;
    }

    function reduce(AddressSet storage set, function(address) external view returns (uint256) func)
        internal
        view
        returns (uint256)
    {
        uint256 aggregated = 0;
        for (uint256 i = 0; i < set.addrs.length; i++) {
            aggregated += func(set.addrs[i]);
        }
        return aggregated;
    }

    function forEach(AddressSet storage set, function(address) external returns (bool) func) internal returns (bool) {
        bool alltrue = true;
        for (uint256 i; i < set.addrs.length; ++i) {
            alltrue = alltrue && func(set.addrs[i]);
        }
        return alltrue;
    }

    function rand(AddressSet storage set, uint256 seed) internal returns (address) {
        address selected;
        if (set.addrs.length > 0) {
            selected = set.addrs[seed % set.addrs.length];
        } else {
            // random address that is not 0x0
            selected = 0xe66f486C5A923Fad83Ac6bdf493A480333842ffe;
            add(set, selected);
        }
        return selected;
    }
}
