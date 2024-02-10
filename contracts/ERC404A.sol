// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * This is an improved contract based on the ERC404's concept with ERC721A gas optimization,
 * allowing a relatively low gas cost for minting and transferring tokens for a larger number of tokens.
 *
 * The ERC20 data is saved as an auxiliary data structure to the ERC721A data structure, allowing the
 * ERC404A contract to have a single storage slot for each token, and acts as both an ERC721 and ERC20
 * without having to re-create the ERC20 structure.
 *
 * ERC404 uses the term "fractionalized representation" to represent the ERC20 balance of the ERC404A contract.
 * The fractionalized representation is the ERC20 balance multiplied by 1e18, and the term "native representation"
 * is the ERC721 balance.
 *
 * ERC404 also implemented a whitelist system to skip ERC721 minting and burning for certain addresses, such as pairs,
 * routers, etc, to save gas during transfers.
 *
 * Because of the avaliable aux space is only 256 - 192 = 64 bits, the total supported token amount to mint is 2^64 tokens,
 * i.e. this contract requires migration rougly after ~2^64 ERC721A transfers, thus the fractionalized representation of
 * the ERC20 balance uses uint64. As of Feb 1 2024, comparing to
 * Azuki: <200,000 transfers lifetime
 * BAYC: <270,000 transfers lifetime
 * CryptoPunk: <60,000 transfers lifetime
 * Using 2^64 transfers is a very large number, and it is unlikely to be reached in the near future.
 *
 * This should be compatible with the ERC404 standard.
 **/

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC721A/ERC721AQueryable.sol";

contract ERC404A is ERC721AQueryable, Ownable {
    // custom event for ERC20
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ERC20Transfer(address indexed from, address indexed to, uint256 value);
    // ERC721Approval is defined in ERC721A to replace its Approval

    uint256 public constant MAX_SUPPLY = 2 ** 64 - 1;

    /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
    mapping(address => bool) public whitelist;

    /// @dev Allowance of user in fractional representation
    mapping(address => mapping(address => uint256)) public allowance;

    struct OwnedRange {
        //? This may be replaced with uint128 to further save gas,
        //? but it will reduce the maximum supported token amount by half
        uint256 start;
        uint256 end;
    }

    /// @dev User's owned ERC721A token Ids, this is by far the most gas consuming operation
    mapping(address => OwnedRange[]) public ownedTokenIdRanges;

    /// @dev Base URL for metadata
    string internal _baseUrl;

    constructor(string memory _name, string memory _symbol) ERC721A(_name, _symbol) {}

    // =============================================================
    //                      ERC404 OPERATIONS
    // =============================================================

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setWhitelist(address target, bool state) public onlyOwner {
        whitelist[target] = state;
    }

    /// @notice Function for token approvals
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function approve(address spender, uint256 amountOrId) public payable override(ERC721A, IERC721A) {
        if (amountOrId <= _totalMinted()) {
            super.approve(spender, amountOrId);
        } else {
            allowance[msg.sender][spender] = amountOrId;
            emit Approval(msg.sender, spender, amountOrId);
        }
    }

    /// @notice Function for mixed transfers
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function transferFrom(address from, address to, uint256 amountOrId) public payable override(ERC721A, IERC721A) {
        if (amountOrId <= _totalMinted()) {
            // transfer ERC721A
            super.transferFrom(from, to, amountOrId);

            // write the updated ERC20 into aux data
            _setAux(from, _getAux(from) - 1e18);
            _setAux(to, _getAux(to) + 1e18);

            // update the ownedTokenIdRanges
            OwnedRange[] storage ranges = ownedTokenIdRanges[from];
            uint256 len = ranges.length;
            for (uint256 i = 0; i < len; i++) {
                if (ranges[i].start <= amountOrId && amountOrId <= ranges[i].end) {
                    if (ranges[i].start == ranges[i].end) {
                        // if the range only contains a single token id, remove it
                        // todo verify if this can pass if the ranges only has one element
                        if (len > 1) {
                            ranges[i] = ranges[len - 1];
                        }
                        ranges.pop();
                    } else {
                        // if the range contains multiple token ids, split it and remove the transferred token id
                        uint256 originalEnd = ranges[i].end;
                        ranges[i].end = amountOrId - 1;
                        ownedTokenIdRanges[to].push(OwnedRange({start: amountOrId + 1, end: originalEnd}));
                    }
                    break;
                }
            }

            emit ERC20Transfer(from, to, 1e18);
        } else {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amountOrId;

            _transfer(from, to, amountOrId);
        }
    }

    /// @notice Function for fractional transfers
    function transfer(address to, uint256 amount) public virtual {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Internal function for fractional transfers
    function _transfer(address from, address to, uint256 amount) internal {
        uint256 balanceBeforeSender = _getAux(from);
        uint256 balanceBeforeReceiver = _getAux(to);

        // This should also check if the sender has enough balance
        _setAux(from, uint64(balanceBeforeSender - amount));
        _setAux(to, uint64(balanceBeforeSender + amount));

        // Skip burn for whitelisted addresses
        if (!whitelist[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / 1e18) - (_getAux(from) / 1e18);
            _sequentialBurn(from, tokens_to_burn);
        }

        // Skip minting for whitelisted addresses
        if (!whitelist[to]) {
            uint256 tokens_to_mint = (balanceOf(to) / 1e18) - (balanceBeforeReceiver / 1e18);
            _mint(to, tokens_to_mint);
            ownedTokenIdRanges[to].push(OwnedRange({start: totalSupply() - tokens_to_mint, end: totalSupply() - 1}));
        }

        emit ERC20Transfer(from, to, amount);
    }

    // =============================================================
    //                      ERC404 METADATA
    // =============================================================

    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @dev Total supply in fractionalized representation
    function totalSupply() public view override(ERC721A, IERC721A) returns (uint256) {
        return super.totalSupply() * 1e18;
    }

    /// @dev Balance of user in fractional representation
    function balanceOf(address owner) public view override(ERC721A, IERC721A) returns (uint256) {
        return super.balanceOf(owner) * 1e18;
    }

    function setBaseUrl(string memory baseUrl) external onlyOwner {
        _baseUrl = baseUrl;
    }

    // =============================================================
    //                      ERC404A OPERATIONS
    // =============================================================

    /// @dev sequential burn, the highest gas consumption, we will loop through the ownedTokenIdRanges
    ///      to get each range and burn until the amount is reached, also updating the ownedTokenIdRanges
    function _sequentialBurn(address from, uint256 burnAmount) internal {
        OwnedRange[] storage ranges = ownedTokenIdRanges[from];
        uint256 burnedAmount = 0;

        for (uint256 i = 0; i < ranges.length; i++) {
            // search for the owned token ids within this range
            uint256[] memory ownedTokens = tokensOfOwnerIn(from, ranges[i].start, ranges[i].end);

            // case if the ownedTokens can all be burned
            if (ownedTokens.length <= burnAmount - burnedAmount) {
                burnedAmount += ownedTokens.length;
                for (uint256 j = 0; j < ownedTokens.length; j++) {
                    _burn(ownedTokens[j]);
                }
                ranges[i] = ranges[ranges.length - 1];
                ranges.pop();
                if (burnedAmount == burnAmount) {
                    break;
                }
                continue;
            }

            // case if the ownedTokens cannot all be burned
            for (uint256 j = 0; j < burnAmount - burnedAmount; j++) {
                _burn(ownedTokens[j]);
            }
            burnedAmount = burnAmount;
            // update the range
            ranges[i].start = ownedTokens[burnAmount - burnedAmount];
            break;
        }
    }
}
