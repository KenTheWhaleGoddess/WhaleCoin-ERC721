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
    
    uint256 public _presaleTime = 1629757800; // In the past
    uint256 public _saleTime = 1630695403; // 	Fri Sep 03 2021 18:56:43 PST

    uint256 public _presaleSupply = 3;
    uint256 public _supply = 5; 

    string private _baseTokenURI;

    // Faciliating the needed functionality for the presale
    mapping(address => bool) addressToPreSaleEntry;
    
    

    // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;


    constructor () ERC721 ("WhaleCoin","WHALE")  {
        tokenCounter = 0;
    }

    function createCollectiblesForPresale(uint256 _count) public payable {
        require(presaleIsOpen(), "Presale is not yet open");
        require(_count <= _maxPerTx, "Cant mint more than mintMax");
        require(isWalletInPresale(msg.sender), "Wallet isnt in presale! Doh!");
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

    function wenPresale() public view returns (uint256) {
        return _presaleTime;
    }

    function wenSale() public view returns (uint256) {
        return _saleTime;
    }

    function saleIsOpen() public view returns (bool) {
        return (block.timestamp >= _saleTime);
    }

    function presaleIsOpen() public view returns (bool) {
        return (block.timestamp >= _presaleTime);
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

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    function withdrawAll() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}