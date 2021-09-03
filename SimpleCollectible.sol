//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SimpleCollectible is ERC721, Ownable {
    uint256 public tokenCounter;

    uint256 public _presalePrice = 10000000000000000; //.01 ETH
    uint256 public _price = 50000000000000000; // .05 ETH

    uint256 public _maxPerTx = 10; // Set to one higher than actual, to save gas on lte/gte checks.

    uint256 public _presaleSupply = 3;
    uint256 public _supply = 9; 

    string private _baseTokenURI;
    uint private _saleState; // 0 - No sale. 1 - Presale. 2 - Main Sale.

    // Faciliating the needed functionality for the presale
    mapping(address => bool) addressToPreSaleEntry;

    // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;


    constructor () ERC721 ("WhaleCoin","WHALE")  {
        tokenCounter = 0;
        _saleState = 0;
    }

    function createCollectiblesForPresale(uint256 _count) public payable {
        require(presaleIsOpen(), "Presale is not yet open. See wenPresale and wenSale for more info");
        require(!presaleIsComplete(), "Presale is over. See wenSale for more info");

        require(_count <= _maxPerTx, "Cant mint more than _maxPerTx");
        require(isWalletInPresale(msg.sender), "Wallet isnt in presale! The owner needs to addWalletToPresale.");
        require((_count +tokenCounter) <= _presaleSupply, "Ran out of NFTs!");
        require(msg.value >= (_presalePrice * _count), "Ether value sent is not correct");

        createCollectibles(_count);
    }

    function createCollectiblesForSale(uint256 _count) public payable {
        require(saleIsOpen(), "Sale is not yet open");
        require(_count <= _maxPerTx, "Cant mint more than mintMax");
        require((_count +tokenCounter) <= _supply, "Ran out of NFTs! Sry!");
        require(msg.value >= (_presalePrice * _count), "Ether value sent is not correct");

        createCollectibles(_count);
    }

    function createCollectibles(uint256 _count) private {
        for(uint i = 0; i < _count; i++) {
            createCollectible();
        }
    }

    function createCollectible() private {
            uint256 newItemId = tokenCounter;

            _safeMint(msg.sender, newItemId);
            _setTokenURI(newItemId, tokenURI(newItemId));
            tokenCounter = tokenCounter + 1;
    }

    function getMaxMintsPerTransaction() public view returns (uint256) {
        return _maxPerTx;
    }

    function wenPresale() public view returns (string memory) {
        return presaleIsOpen() ? "now" : "#soon";
    }

    function wenSale() public view returns (string memory) {
        return saleIsOpen() ? "now" : "#soon";
    }

    function saleIsOpen() public view returns (bool) {
        return _saleState == 2;
    }

    function presaleIsOpen() public view returns (bool) {
        return (_saleState >= 1);
    }
    function presaleIsComplete() public view returns (bool) {
        return tokenCounter < (_presaleSupply - 1);
    }
    
    function getSaleState() private view returns (uint){
        return _saleState;
    }
    
    function setSaleState(uint saleState) public onlyOwner {
        _saleState = saleState;
    }

    function isWalletInPresale(address _address) public view returns (bool) {
        return addressToPreSaleEntry[_address];
    }
    function addWalletToPreSale(address _address) public onlyOwner {
        addressToPreSaleEntry[_address] = true;
    }
    
    

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function getBaseURI() public view returns (string memory){
        return _baseTokenURI;
    }
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    function withdrawAll() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}
