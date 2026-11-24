// SPDX-License-Identifier: MIT
// TEST ONLY. This is the source of the Agent ID registry as verified on Sourcify for
// 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F on BNB Smart Chain (SPACE ID, MIT), unchanged below this
// header. Local tests use it so that they run against the registry's real rules. It is never deployed to mainnet.
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Permanent, one-to-one soulbound handle registry.
contract HandleRegistry is ERC721, EIP712, Ownable2Step {
    uint8 public constant LEN_CEILING = 64;
    bytes32 private constant REGISTER_TYPEHASH = keccak256("Register(string handle,address owner,uint256 deadline)");
    mapping(address => string) public handleOf;
    address public signer;
    uint8 public minLen;
    uint8 public maxLen;
    string public baseURI;
    string public uriSuffix;

    event Registered(bytes32 indexed labelhash, address indexed owner, string handle);
    event AdminRegistered(bytes32 indexed labelhash, address indexed owner, string handle);
    event SignerChanged(address indexed signer);
    event LengthBoundsChanged(uint8 minLen, uint8 maxLen);
    event URIPartsChanged(string baseURI, string uriSuffix);

    error SignatureExpired();
    error InvalidHandle();
    error HandleTaken();
    error AddressHasHandle();
    error BadSignature();
    error BadBounds();
    error Soulbound();

    constructor(address initialSigner, uint8 initialMin, uint8 initialMax, string memory uri, string memory suffix)
        ERC721("SPACE ID Agent ID", "AI") EIP712("HandleRegistry", "1") Ownable(msg.sender)
    {
        signer = initialSigner;
        _setLengthBounds(initialMin, initialMax);
        _setURIParts(uri, suffix);
        emit SignerChanged(initialSigner);
    }

    function register(string calldata handle, uint256 deadline, bytes calldata sig) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (!isValidHandle(handle)) revert InvalidHandle();
        bytes32 label = keccak256(bytes(handle));
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(REGISTER_TYPEHASH, label, msg.sender, deadline)));
        if (ECDSA.recover(digest, sig) != signer) revert BadSignature();
        _mintHandle(handle, label, msg.sender);
        emit Registered(label, msg.sender, handle);
    }

    function adminRegister(string calldata handle, address to) external onlyOwner {
        if (!isValidHandle(handle)) revert InvalidHandle();
        bytes32 label = keccak256(bytes(handle));
        _mintHandle(handle, label, to);
        emit AdminRegistered(label, to, handle);
    }

    function _mintHandle(string calldata handle, bytes32 label, address to) private {
        if (bytes(handleOf[to]).length != 0) revert AddressHasHandle();
        if (_ownerOf(uint256(label)) != address(0)) revert HandleTaken();
        handleOf[to] = handle;
        // Smart accounts need not implement ERC721Receiver for an immovable token.
        _mint(to, uint256(label));
    }

    function isValidHandle(string calldata handle) public view returns (bool) {
        bytes calldata b = bytes(handle);
        if (b.length < minLen || b.length > maxLen) return false;
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (!((c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39))) return false;
        }
        return true;
    }

    function ownerOfHandle(string calldata handle) external view returns (address) {
        return _ownerOf(uint256(keccak256(bytes(handle))));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address holder = ownerOf(tokenId);
        if (bytes(baseURI).length == 0) return "";
        return string.concat(baseURI, handleOf[holder], uriSuffix);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override { revert Soulbound(); }
    function setApprovalForAll(address, bool) public pure override { revert Soulbound(); }

    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit SignerChanged(newSigner);
    }

    function setLengthBounds(uint8 newMin, uint8 newMax) external onlyOwner {
        _setLengthBounds(newMin, newMax);
    }

    function _setLengthBounds(uint8 newMin, uint8 newMax) private {
        if (newMin == 0 || newMin > newMax || newMax > LEN_CEILING) revert BadBounds();
        minLen = newMin;
        maxLen = newMax;
        emit LengthBoundsChanged(newMin, newMax);
    }

    function setURIParts(string calldata uri, string calldata suffix) external onlyOwner {
        _setURIParts(uri, suffix);
    }

    function _setURIParts(string memory uri, string memory suffix) private {
        baseURI = uri;
        uriSuffix = suffix;
        emit URIPartsChanged(uri, suffix);
    }
}
