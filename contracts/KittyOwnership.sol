/// @title The facet of the CryptoKitties core contract that manages ownership, ERC-721 (draft) compliant.
/// @author Axiom Zen (https://www.axiomzen.co)
/// @dev Ref: https://github.com/ethereum/EIPs/issues/721
///  See the KittyCore contract documentation to understand how the various contract facets are arranged.
/**
 * Kitties代币化，把kitties和ERC-721结合起来：CryptoKitties核心合约的管理所有权的一个方面，符合ERC-721(草案)的要求。
 */

contract KittyOwnership is KittyBase, ERC721 {

    /// @notice Name and symbol of the non fungible token, as defined in ERC721.
    // 不可替换令牌的名称和符号，如ERC721中定义的。
    string public constant name = "CryptoKitties";
    string public constant symbol = "CK";

    // The contract that will return kitty metadata
    // 将返回kitty元数据的合约
    ERC721Metadata public erc721Metadata;

    bytes4 constant InterfaceSignature_ERC165 =
        bytes4(keccak256('supportsInterface(bytes4)'));

    bytes4 constant InterfaceSignature_ERC721 =
        bytes4(keccak256('name()')) ^
        bytes4(keccak256('symbol()')) ^
        bytes4(keccak256('totalSupply()')) ^
        bytes4(keccak256('balanceOf(address)')) ^
        bytes4(keccak256('ownerOf(uint256)')) ^
        bytes4(keccak256('approve(address,uint256)')) ^
        bytes4(keccak256('transfer(address,uint256)')) ^
        bytes4(keccak256('transferFrom(address,address,uint256)')) ^
        bytes4(keccak256('tokensOfOwner(address)')) ^
        bytes4(keccak256('tokenMetadata(uint256,string)'));

    /// @notice Introspection interface as per ERC-165 (https://github.com/ethereum/EIPs/issues/165).
    ///  Returns true for any standardized interfaces implemented by this contract. We implement
    ///  ERC-165 (obviously!) and ERC-721.
    // 对于由此合约实现的任何标准化接口，返回true。我们实现了ERC-165(显然!)和ERC-721。
    function supportsInterface(bytes4 _interfaceID) external view returns (bool)
    {
        // DEBUG ONLY
        //require((InterfaceSignature_ERC165 == 0x01ffc9a7) && (InterfaceSignature_ERC721 == 0x9a20483d));

        return ((_interfaceID == InterfaceSignature_ERC165) || (_interfaceID == InterfaceSignature_ERC721));
    }

    /// @dev Set the address of the sibling contract that tracks metadata.
    ///  CEO only.
    // 设置跟踪元数据的兄弟契约的地址。只允许CEO调用
    function setMetadataAddress(address _contractAddress) public onlyCEO {
        erc721Metadata = ERC721Metadata(_contractAddress);
    }

    // Internal utility functions: These functions all assume that their input arguments
    // are valid. We leave it to public methods to sanitize their inputs and follow
    // the required logic.
    /**
     * 内部实用程序函数:这些函数都假设它们的输入参数是有效的。我们将它留给公共方法来净化它们的输入并遵循所需的逻辑。
     */

    /// @dev Checks if a given address is the current owner of a particular Kitty.
    /// @param _claimant the address we are validating against.
    /// @param _tokenId kitten id, only valid when > 0
    // 检查给定地址_claimant是否为特定Kitty _tokenId的当前所有者。
    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return kittyIndexToOwner[_tokenId] == _claimant;
    }

    /// @dev Checks if a given address currently has transferApproval for a particular Kitty.
    /// @param _claimant the address we are confirming kitten is approved for.
    /// @param _tokenId kitten id, only valid when > 0
    // 检查给定的地址当前是否具有特定Kitty的transferApproval。即_tokenId是否能够转让给_claimant
    function _approvedFor(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return kittyIndexToApproved[_tokenId] == _claimant;
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    ///  NOTE: _approve() does NOT send the Approval event. This is intentional because
    ///  _approve() and transferFrom() are used together for putting Kitties on auction, and
    ///  there is no value in spamming the log with Approval events in that case.
    // 将地址标记为通过的，从而可调用transferFrom()。这个过程会覆盖以前的任何批准。
    // 特别的，将_approved设置为address(0)则会清除所有转移审批。
    // 注意:_approve()不发送审批事件。这是有意为之的，因为_approve()和transferFrom()一起用于将小猫放到拍卖中，
    // 在这种情况下，用审批事件来垃圾日志没有任何价值。
    function _approve(uint256 _tokenId, address _approved) internal {
        kittyIndexToApproved[_tokenId] = _approved;
    }

    /// @notice Returns the number of Kitties owned by a specific address.
    /// @param _owner The owner address to check.
    /// @dev Required for ERC-721 compliance
    // 返回特定地址所拥有的小猫数量。
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipTokenCount[_owner];
    }

    /// @notice Transfers a Kitty to another address. If transferring to a smart
    ///  contract be VERY CAREFUL to ensure that it is aware of ERC-721 (or
    ///  CryptoKitties specifically) or your Kitty may be lost forever. Seriously.
    /// @param _to The address of the recipient, can be a user or contract.
    /// @param _tokenId The ID of the Kitty to transfer.
    /// @dev Required for ERC-721 compliance.
    // 外部合约：把调用者小猫转移到另一个地址。
    // 如果转移到智能合同，要非常小心，以确保它知道ERC-721(或专门的加密猫)或你的猫可能永远丢失。认真对待。
    function transfer(
        address _to,
        uint256 _tokenId
    )
        external
        whenNotPaused
    {
        // Safety check to prevent against an unexpected 0x0 default.
        // 安全检查以防止出现意外的0x0默认值。
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any kitties (except very briefly
        // after a gen0 cat is created and before it goes on auction).
        // 不允许转让到本合约的地址，以防止意外滥用。这份合约不应该拥有任何小猫(除非是在gen0猫被创造出来并被拍卖之前)。
        require(_to != address(this));
        // Disallow transfers to the auction contracts to prevent accidental
        // misuse. Auction contracts should only take ownership of kitties
        // through the allow + transferFrom flow.
        // 不允许转让到拍卖合约地址，以防止意外滥用。
        // 【注意】拍卖合约只能通过“allow + transferFrom”的方式取得小猫的所有权。
        require(_to != address(saleAuction));
        require(_to != address(siringAuction));

        // You can only send your own cat.
        // 你只能送你自己的猫。
        require(_owns(msg.sender, _tokenId));

        // Reassign ownership, clear pending approvals, emit Transfer event.
        _transfer(msg.sender, _to, _tokenId);
    }

    /// @notice Grant another address the right to transfer a specific Kitty via
    ///  transferFrom(). This is the preferred flow for transfering NFTs to contracts.
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _tokenId The ID of the Kitty that can be transferred if this call succeeds.
    /// @dev Required for ERC-721 compliance.
    // 授予另一个地址通过transferFrom()转移特定的Kitty的权利。这是将NFTs转移到合约地址的首选流程。
    function approve(
        address _to, // 被批准转让的地址。如果是地址(0)则清除所有批准。
        uint256 _tokenId // 如果调用成功，可以转移的Kitty的ID。
    )
        external
        whenNotPaused
    {
        // Only an owner can grant transfer approval.
        // 只有猫的主人才能批准转让。
        require(_owns(msg.sender, _tokenId));

        // Register the approval (replacing any previous approval).
        _approve(_tokenId, _to);

        // Emit approval event.
        Approval(msg.sender, _to, _tokenId);
    }

    /// @notice Transfer a Kitty owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the Kitty to be transfered.
    /// @param _to The address that should take ownership of the Kitty. Can be any address,
    ///  including the caller.
    /// @param _tokenId The ID of the Kitty to be transferred.
    /// @dev Required for ERC-721 compliance.
    // 将另一个地址拥有的小猫转移，该地址之前已获得猫的所有者的转移批准。
    function transferFrom(
        address _from, // 猫的主人的地址
        address _to, // 要转给的地址，可以是调用者
        uint256 _tokenId // 要转让的猫的id
    )
        external
        whenNotPaused
    {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any kitties (except very briefly
        // after a gen0 cat is created and before it goes on auction).
        require(_to != address(this));
        // Check for approval and valid ownership
        require(_approvedFor(msg.sender, _tokenId));
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    /// @notice Returns the total number of Kitties currently in existence.
    /// @dev Required for ERC-721 compliance.
    // 当前猫的总量
    function totalSupply() public view returns (uint) {
        return kitties.length - 1;
    }

    /// @notice Returns the address currently assigned ownership of a given Kitty.
    /// @dev Required for ERC-721 compliance.
    function ownerOf(uint256 _tokenId)
        external
        view
        returns (address owner)
    {
        owner = kittyIndexToOwner[_tokenId];

        require(owner != address(0));
    }

    /// @notice Returns a list of all Kitty IDs assigned to an address.
    /// @param _owner The owner whose Kitties we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire Kitty array looking for cats belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    // 返回给定地址拥有的猫的id的列表
    // 【注意】智能合约代码决不能调用此方法。首先，它相当昂贵(它遍历整个Kitty数组，寻找属于所有者的猫)，
    // 但是它也返回一个动态数组，动态数组只支持web3调用，而不支持合约到合约的调用。
    function tokensOfOwner(address _owner) external view returns(uint256[] ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount); // 这里新建了一个动态数组。ps: 局部变量最好显式用memory类型。
            uint256 totalCats = totalSupply();
            uint256 resultIndex = 0;

            // We count on the fact that all cats have IDs starting at 1 and increasing
            // sequentially up to the totalCat count.
            uint256 catId;

            for (catId = 1; catId <= totalCats; catId++) {
                if (kittyIndexToOwner[catId] == _owner) {
                    result[resultIndex] = catId;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    /// @dev Adapted from memcpy() by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    // 存储槽chunk的复制：把_src往后的_len个字节复制到_dest往后的_len个字节
    // 【注意】
    //    1) solidity语言中，一个槽chunk有32个字节
    //    2) 汇编语言的操作单位都是一个槽chunk，也就是32字节。例如下面的mload和mstore，都是一次性操作32个字节
    function _memcpy(uint _dest, uint _src, uint _len) private view {
        // Copy word-length chunks while possible
        // 第一步：完整地复制长度为一个字（也就是32字节）的槽
        for(; _len >= 32; _len -= 32) {
            assembly {
                mstore(_dest, mload(_src)) // 一次存32个字节
            }
            _dest += 32;
            _src += 32;
        }

        // Copy remaining bytes
        // 第二步：复制剩下的不足32个字节的数据
        // 使用256是因为一个字节8位，2**8等于256（一个字节有256种可能的组合方式）。
        // 256的(32 - _len)次方，也就是32-_len个字节的可能的组合数。再减去1，则所有的位全部为1。
        // 要注意的是，这是不需要复制的后面32-_len个字节，所有位都是1。而需要复制的_len字节，所有位都为0
        // 搞这个mask的原因，就是只复制一个槽的前_len个字节，后面32-_len字节都保持原样
        uint256 mask = 256 ** (32 - _len) - 1; 
        assembly {
            let srcpart := and(mload(_src), not(mask)) // not(mask)，则前_len个字节的位都为1，后32-_len字节的位都为0。和运算后，前_len个字节的位与_src的一致，后32-_len字节的位都为0
            let destpart := and(mload(_dest), mask) // 前_len个字节的位都为0，后32-_len字节的位不变
            mstore(_dest, or(destpart, srcpart)) // 前_len个字节的位用srcpart的，后_32-_len字节的位用destpart的
        }
    }

    /// @dev Adapted from toString(slice) by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _toString(bytes32[4] _rawBytes, uint256 _stringLength) private view returns (string) {
        var outputString = new string(_stringLength);
        uint256 outputPtr;
        uint256 bytesPtr;

        assembly {
            outputPtr := add(outputString, 32) // 32的ASCII编码为空格，相当于outputString里只有一个空格，且outputPtr指向这个空格
            bytesPtr := _rawBytes
        }

        _memcpy(outputPtr, bytesPtr, _stringLength);

        return outputString;
    }

    /// @notice Returns a URI pointing to a metadata package for this token conforming to
    ///  ERC-721 (https://github.com/ethereum/EIPs/issues/721)
    /// @param _tokenId The ID number of the Kitty whose metadata should be returned.
    function tokenMetadata(uint256 _tokenId, string _preferredTransport) external view returns (string infoUrl) {
        require(erc721Metadata != address(0));
        bytes32[4] memory buffer;
        uint256 count;
        (buffer, count) = erc721Metadata.getMetadata(_tokenId, _preferredTransport);

        return _toString(buffer, count);
    }
}
