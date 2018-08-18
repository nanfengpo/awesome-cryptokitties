/// @title Base contract for CryptoKitties. Holds all common structs, events and base variables.
/// @author Axiom Zen (https://www.axiomzen.co)
/// @dev See the KittyCore contract documentation to understand how the various contract facets are arranged.
/**
 * CryptoKitties的基础合约。保存所有公共结构、事件和基本变量。
 */

contract KittyBase is KittyAccessControl {
    /*** EVENTS ***/

    /// @dev The Birth event is fired whenever a new kitten comes into existence. This obviously
    ///  includes any time a cat is created through the giveBirth method, but it is also called
    ///  when a new gen0 cat is created.
    // 只要有一只小猫出生，出生事件就会被触发。这显然包括任何通过giveBirth方法创建的猫，但是当一个新的gen0猫被创建时，它也会被调用。
    event Birth(address owner, uint256 kittyId, uint256 matronId, uint256 sireId, uint256 genes);

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a kitten
    ///  ownership is assigned, including births.
    // 在ERC721的当前草案中定义的传输事件。每一次小猫的所有权被分配时触发，包括出生。
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/

    /// @dev The main Kitty struct. Every cat in CryptoKitties is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    // 主要的结构体。加密猫中的每只猫都由这个结构的一个对象来表示，所以我们非常小心地确保它精确地匹配到两个256位的字。
    // 注意，这个结构中成员的顺序很重要，因为Ethereum所使用的字节填充规则。
    struct Kitty {
        // The Kitty's genetic code is packed into these 256-bits, the format is
        // sooper-sekret! A cat's genes never change.
        // 小猫的遗传密码被打包成256位，格式是sooper-sekret!猫的基因永远不会改变。
        uint256 genes;

        // The timestamp from the block when this cat came into existence.
        uint64 birthTime;

        // The minimum timestamp after which this cat can engage in breeding
        // activities again. This same timestamp is used for the pregnancy
        // timer (for matrons) as well as the siring cooldown.
        // 这只猫可以再次进行繁殖活动的最小时间戳。此时间戳同时用于怀孕计时器(母猫)和siring（公猫）冷却时间。
        uint64 cooldownEndBlock;

        // The ID of the parents of this kitty, set to 0 for gen0 cats.
        // Note that using 32-bit unsigned integers limits us to a "mere"
        // 4 billion cats. This number might seem small until you realize
        // that Ethereum currently has a limit of about 500 million
        // transactions per year! So, this definitely won't be a problem
        // for several years (even as Ethereum learns to scale).
        // 这只小猫的父母的ID，对gen0猫设置为0。注意，使用32位无符号整数限制了我们“仅仅”40亿只猫。
        // 这个数字可能看起来很小，直到你意识到Ethereum目前每年大约有5亿笔交易的限制!
        // 因此，这在几年内绝对不会成为一个问题(即使Ethereum学会了规模化)。
        // 【注意】Id和上面的genes是两码事。Id是从0开始以自然数增长的。
        uint32 matronId; // 母亲
        uint32 sireId; // 父亲

        // Set to the ID of the sire cat for matrons that are pregnant,
        // zero otherwise. A non-zero value here is how we know a cat
        // is pregnant. Used to retrieve the genetic material for the new
        // kitten when the birth transpires.
        // 为怀孕的母猫设置sire猫的ID，否则为零。一个非零值是我们如何知道猫怀孕的(和哪只公猫做爱)。用来获取新小猫出生时的遗传物质。
        uint32 siringWithId; // 只有怀孕的母猫才不为0

        // Set to the index in the cooldown array (see below) that represents
        // the current cooldown duration for this Kitty. This starts at zero
        // for gen0 cats, and is initialized to floor(generation/2) for others.
        // Incremented by one for each successful breeding action, regardless
        // of whether this cat is acting as matron or sire.
        // 设置为冷却时间常量数组中的索引(参见下面)，该索引表示此Kitty当前繁殖的冷却时间。
        // 对于gen0 cats，初始值为0，而对于其他对象，初始值为floor(generation/2)。
        // 无论这只猫是母猫还是母猫，每一次成功的繁殖都会加一。
        uint16 cooldownIndex;

        // The "generation number" of this cat. Cats minted by the CK contract
        // for sale are called "gen0" and have a generation number of 0. The
        // generation number of all other cats is the larger of the two generation
        // numbers of their parents, plus one.
        // (i.e. max(matron.generation, sire.generation) + 1)
        // 这只猫的“世代”。CK公司生产的猫被称为“gen0”，代数为0。
        // 其他所有猫的世代数是它们父母的两世代数中较大的，再加上1。
        uint16 generation;
    }

    /*** CONSTANTS ***/

    /// @dev A lookup table indicating the cooldown duration after any successful
    ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    ///  for sires. Designed such that the cooldown roughly doubles each time a cat
    ///  is bred, encouraging owners not to just keep breeding the same cat over
    ///  and over again. Caps out at one week (a cat can breed an unbounded number
    ///  of times, and the maximum cooldown is always seven days).
    
    // 一个查找表，指示在任何成功的繁殖行为后的冷却时间，称为“怀孕时间”的母猴和“siring冷却时间”的sires。
    // 这种设计使得每只猫繁殖一次的冷却时间大约增加一倍，从而鼓励主人不要一遍又一遍地繁殖同一只猫。
    // 限制在一个星期(一只猫可以繁殖无限次，最大的冷却时间总是七天)。
    uint32[14] public cooldowns = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    // 当前块之间的秒数的近似值
    uint256 public secondsPerBlock = 15;

    /*** STORAGE ***/

    /// @dev An array containing the Kitty struct for all Kitties in existence. The ID
    ///  of each cat is actually an index into this array. Note that ID 0 is a negacat,
    ///  the unKitty, the mythical beast that is the parent of all gen0 cats. A bizarre
    ///  creature that is both matron and sire... to itself! Has an invalid genetic code.
    ///  In other words, cat ID 0 is invalid... ;-)
    // 一个包含所有现存小猫的Kitty struct的数组。每个cat的ID实际上是这个数组的索引。
    // 注意，ID 0是一个negacat, unKitty，是所有gen0猫的始祖。
    // 一个古怪的生物，既是母猫又生出了自己!有一个无效的遗传密码。换句话说，cat ID 0是无效的…:-)
    Kitty[] kitties;

    /// @dev A mapping from cat IDs to the address that owns them. All cats have
    ///  some valid owner address, even gen0 cats are created with a non-zero owner.
    // 从cat id到拥有它们的地址的映射。所有的猫都有一个有效的所有者地址，即使是gen0猫也有一个非0的所有者。
    mapping (uint256 => address) public kittyIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    // 从所有者地址到地址所拥有的猫的数量的映射。在balanceOf()内部内部使用，以解决所有权计数。
    mapping (address => uint256) ownershipTokenCount;

    /// @dev A mapping from KittyIDs to an address that has been approved to call
    ///  transferFrom(). Each Kitty can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.
    // 从KittyIDs映射到已批准调用transferFrom()的地址，这个地址可以把这只小猫转给其他人，即使此地址不是小猫的主人。
    // 每只猫在任何时候只能有一个经批准的转帐地址。零值表示没有未得到批准。
    mapping (uint256 => address) public kittyIndexToApproved;

    /// @dev A mapping from KittyIDs to an address that has been approved to use
    ///  this Kitty for siring via breedWith(). Each Kitty can only have one approved
    ///  address for siring at any time. A zero value means no approval is outstanding.
    // 从KittyIDs映射到已批准使用此Kitty通过breedWith()进行siring的地址。也就是一只猫能授精的对象。
    // 每个小猫在任何时候只能有一个被批准的用于siring地址。零值表示没有未得到批准。
    mapping (uint256 => address) public sireAllowedToAddress;

    /// @dev The address of the ClockAuction contract that handles sales of Kitties. This
    ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    ///  initiated every 15 minutes.
    // ClockAuction子类合同的地址，用于处理小猫买卖。这个合同同时处理对等销售和每15分钟启动一次的gen0销售。
    SaleClockAuction public saleAuction;

    /// @dev The address of a custom ClockAuction subclassed contract that handles siring
    ///  auctions. Needs to be separate from saleAuction because the actions taken on success
    ///  after a sales and siring auction are quite different.
    // ClockAuction子类合同的地址，用于处理siring拍卖。
    // “Siring”指的是拍卖你的猫的交配权，在那里另一个用户可以付钱给你以太，让你的猫与他们一起繁殖。
    // 需要与销售拍卖分开，因为在销售和siring拍卖成功后采取的行动是完全不同的。
    SiringClockAuction public siringAuction;

    /// @dev Assigns ownership of a specific Kitty to an address.
    // 将某只小猫的所有权分配给一个地址。
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of kittens is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++; // _to地址拥有的猫的数量加一
        // transfer ownership
        kittyIndexToOwner[_tokenId] = _to; // 更改_tokenID这只猫的所有者
        // When creating new kittens _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--; // _from地址拥有的猫的数量加一
            // once the kitten is transferred also clear sire allowances
            // 一旦小猫被转移，也删除了这只猫能授精的对象。
            delete sireAllowedToAddress[_tokenId];
            // clear any previously approved ownership exchange
            // 清除任何先前批准的所有权交换
            delete kittyIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        // 触发事件
        Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new kitty and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Birth event
    ///  and a Transfer event.
    // 一种内部方法，用于创建和存储一个新的kitty。这个方法不做任何检查，只在输入数据有效时才调用。将生成出生事件和转移事件。
    /// @param _matronId The kitty ID of the matron of this cat (zero for gen0)
    /// @param _sireId The kitty ID of the sire of this cat (zero for gen0)
    /// @param _generation The generation number of this cat, must be computed by caller.
    /// @param _genes The kitty's genetic code.
    /// @param _owner The inital owner of this cat, must be non-zero (except for the unKitty, ID 0)
    function _createKitty(
        uint256 _matronId, // 母亲
        uint256 _sireId, // 父亲
        uint256 _generation, // 世代
        uint256 _genes, // 基因码
        address _owner // 所有者
    )
        internal
        returns (uint)
    {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createKitty() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        // 这些要求并不是绝对必要的，我们的调用代码应该确保这些条件不会被破坏。
        // 然而!_createKitty()已经是一个昂贵的调用(用于存储)了，而且要特别小心地确保我们的数据结构总是有效的，这也没什么坏处。
        // 【注意】记住这种验证是否溢出的方法！！！
        require(_matronId == uint256(uint32(_matronId)));
        require(_sireId == uint256(uint32(_sireId)));
        require(_generation == uint256(uint16(_generation)));

        // New kitty starts with the same cooldown as parent gen/2
        uint16 cooldownIndex = uint16(_generation / 2);
        if (cooldownIndex > 13) {
            cooldownIndex = 13;
        }

        // 临时变量memory
        //【注意】函数内部的局部变量应当显示使用memory类型！！！
        Kitty memory _kitty = Kitty({
            genes: _genes,
            birthTime: uint64(now),
            cooldownEndBlock: 0,
            matronId: uint32(_matronId),
            sireId: uint32(_sireId),
            siringWithId: 0,
            cooldownIndex: cooldownIndex,
            generation: uint16(_generation)
        });
        uint256 newKittenId = kitties.push(_kitty) - 1; // 此猫的ID。push()函数会返回新的数组的长度

        // It's probably never going to happen, 4 billion cats is A LOT, but
        // let's just be 100% sure we never let this happen.
        // 这可能永远不会发生，40亿只猫是很多，但让我们100%确信我们永远不会让它发生。
        require(newKittenId == uint256(uint32(newKittenId)));

        // emit the birth event
        Birth(
            _owner,
            newKittenId,
            uint256(_kitty.matronId),
            uint256(_kitty.sireId),
            _kitty.genes
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newKittenId);

        return newKittenId;
    }

    // Any C-level can fix how many seconds per blocks are currently observed.
    // 修改每个区块的秒数。这个应当由C级别的人根据当前以太坊网络实际情况来调整
    function setSecondsPerBlock(uint256 secs) external onlyCLevel {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }
}
