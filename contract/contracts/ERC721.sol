pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./IERC721.sol";
import "./IERC721TokenReceiver.sol";
import "./IERC721Metadata.sol";

contract ERC721 is IERC721, IERC721Metadata, ERC165 {
    using SafeMath for uint256;
    using Strings for uint256;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    string internal _name;

    string internal _symbol;

    string internal _baseTokenURI;

    address _owner;

    mapping(uint256 => address) internal _idToOwner;

    mapping(uint256 => address) internal _idToApproval;

    mapping(address => uint256) private _ownerToNFTokenCount;

    mapping(address => mapping(address => bool)) _ownerToOperators;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only owner can call");
        _;
    }

    modifier canTransfer(uint256 _tokenId) {
        address tokenOwner = _idToOwner[_tokenId];

        require(
            tokenOwner == msg.sender ||
                _idToApproval[_tokenId] == msg.sender ||
                _ownerToOperators[tokenOwner][msg.sender],
            "Not allowed to transfer"
        );
        _;
    }

    modifier canOperate(uint256 _tokenId) {
        address tokenOwner = _idToOwner[_tokenId];
        require(
            tokenOwner == msg.sender ||
                _ownerToOperators[tokenOwner][msg.sender],
            "Not allowed to operate"
        );
        _;
    }

    modifier validNFToken(uint256 _tokenId) {
        require(_idToOwner[_tokenId] != address(0), "NFT doesn't exist");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) {
        _owner = msg.sender;
        _name = name;
        _symbol = symbol;
        _baseTokenURI = baseTokenURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function baseTokenURI() public view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        return
            bytes(_baseTokenURI).length > 0
                ? string(abi.encodePacked(_baseTokenURI, tokenId.toString()))
                : "";
    }

    function balanceOf(address owner) external view override returns (uint256) {
        require(owner != address(0), "Address must not be zero");
        return _ownerToNFTokenCount[_owner];
    }

    function ownerOf(uint256 _tokenId)
        external
        view
        override
        returns (address owner)
    {
        owner = _idToOwner[_tokenId];
        require(owner != address(0), "NFT doesn't exist");
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external override validNFToken(_tokenId) canTransfer(_tokenId) {
        _safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external override validNFToken(_tokenId) canTransfer(_tokenId) {
        _safeTransferFrom(_from, _to, _tokenId, "");
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external override validNFToken(_tokenId) canTransfer(_tokenId) {
        address tokenOwner = _idToOwner[_tokenId];
        require(tokenOwner == _from, "Not owner of NFT");
        require(
            _to != address(0),
            "Destination address must not be zero address"
        );

        _transfer(_to, _tokenId);
    }

    function approve(address _approved, uint256 _tokenId)
        external
        override
        validNFToken(_tokenId)
        canOperate(_tokenId)
    {
        address tokenOwner = _idToOwner[_tokenId];
        require(_approved != tokenOwner, "Cannot approve to myself");

        _idToApproval[_tokenId] = _approved;
        emit Approval(tokenOwner, _approved, _tokenId);
    }

    function setApprovalForAll(address _operator, bool _approved)
        external
        override
    {
        _ownerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function getApproved(uint256 _tokenId)
        external
        view
        override
        validNFToken(_tokenId)
        returns (address)
    {
        return _idToApproval[_tokenId];
    }

    function isApprovedForAll(address owner, address operator)
        external
        view
        override
        returns (bool)
    {
        return _ownerToOperators[owner][operator];
    }

    function mint(address _to, uint256 _tokenId) external onlyOwner {
        require(_to != address(0), "Destination address must not be zero");
        require(_idToOwner[_tokenId] == address(0), "The NFT already exists");

        _addNFToken(_to, _tokenId);

        emit Transfer(address(0), _to, _tokenId);
    }

    function _safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) private {
        address tokenOwner = _idToOwner[_tokenId];
        require(tokenOwner == _from, "Not owner of NFT");
        require(
            _to != address(0),
            "Destination address must not be zero address"
        );

        _transfer(_to, _tokenId);

        if (Address.isContract(_to)) {
            bytes4 retval =
                IERC721TokenReceiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    _data
                );
            require(retval == _ERC721_RECEIVED, "Receiver cannot handle NFT");
        }
    }

    function _transfer(address _to, uint256 _tokenId) internal {
        address from = _idToOwner[_tokenId];
        _clearApproval(_tokenId);

        _removeNFToken(from, _tokenId);
        _addNFToken(_to, _tokenId);

        emit Transfer(from, _to, _tokenId);
    }

    function _clearApproval(uint256 _tokenId) private {
        if (_idToApproval[_tokenId] != address(0)) {
            delete _idToApproval[_tokenId];
        }
    }

    function _removeNFToken(address _from, uint256 _tokenId) internal {
        require(_idToOwner[_tokenId] == _from, "Not token owner");

        _ownerToNFTokenCount[_from] = _ownerToNFTokenCount[_from].sub(1);
        delete _idToOwner[_tokenId];
    }

    function _addNFToken(address _to, uint256 _tokenId) internal {
        require(
            _idToOwner[_tokenId] == address(0),
            "Token owner already exists"
        );

        _idToOwner[_tokenId] = _to;
        _ownerToNFTokenCount[_to] = _ownerToNFTokenCount[_to].add(1);
    }
}
