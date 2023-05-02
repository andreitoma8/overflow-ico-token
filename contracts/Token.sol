// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./VestingContract.sol";

contract Token is ERC20, Initializable, Ownable {
    VestingContract public vestingContract;

    // The token allocation
    uint256 public constant TOTAL_SUPPLY = 150_000_000 * 10 ** 18;
    uint256 public constant PUBLIC_SALE = 20_000_000 * 10 ** 18;
    uint256 public constant TEAM_ADVISORS = 15_000_000 * 10 ** 18;
    uint256 public constant MARKETING_PARTNERSHIPS = 30_000_000 * 10 ** 18;
    uint256 public constant RESERVE = 30_000_000 * 10 ** 18;
    uint256 public constant DEVELOPMENT = 30_000_000 * 10 ** 18;
    uint256 public constant COMMUNITY = 20_000_000 * 10 ** 18;
    uint256 public constant TOKEN_SALE_EXPENSES = 5_000_000 * 10 ** 18;

    // Sale variables
    uint256 public constant MINIMUM_BUY = 0.001 ether;
    uint256 public constant MAXIMUM_BUY = 2 ether;
    uint256 public constant SOFT_CAP = 100 ether;
    uint256 public constant HARD_CAP = 500 ether;
    uint256 public constant BONUS_TOKENS = 1_000_000 * 10 ** 18;

    /**
     * @notice Whether the soft cap has been reached.
     */
    bool public softCapReached;

    /**
     * @notice Whether the sale has ended.
     */
    bool public saleEnded;

    /**
     * @notice The total amount of ETH to refund if the hard cap is surpassed.
     */
    uint256 public ethToRefund;

    /**
     * @notice The total amount of ETH raised.
     */
    uint256 public totalRaised;

    /**
     * @notice The amount of contributors.
     */
    uint256 contributors;

    /**
     * @notice Total ETH considered fo the bonus.
     */
    uint256 public totalForBonus;

    /**
     * @notice The start date of the sale in unix timestamp.
     */
    uint256 public start;

    /**
     * @notice The end date of the sale in unix timestamp.
     */
    uint256 public end;

    /**
     * @notice The wallets of the project:
     * [0] = project wallet
     * [1] = team and adivsors address
     * [2] = marketing address
     * [3] = reserve fund address
     * [4] = development fund address
     * [5] = community incentives address
     */
    address[6] wallets;

    /**
     * @notice The amount of ETH contributed by each address.
     */
    mapping(address => uint256) public contributions;

    /**
     * @notice The amount of ETH contributed by each of the first 100 contributors.
     */
    mapping(address => uint256) public eligibleForBonus;

    /**
     * @notice Emits when ETH is contributed during the sale.
     * @param buyer The address of the buyer.
     * @param amount The amount of ETH contributed.
     */
    event EthContributed(address indexed buyer, uint256 amount);

    /**
     * @notice Emits when tokens are claimed.
     * @param claimer The address of the claimer.
     * @param amount The amount of tokens claimed.
     */
    event TokensClaimed(address indexed claimer, uint256 amount);

    /**
     * @notice Emits when ETH is refunded.
     * @param buyer The address of the buyer.
     * @param amount The amount of ETH refunded.
     */
    event EthRefunded(address indexed buyer, uint256 amount);

    /**
     * @notice Emits when the sale is ended.
     * @param totalAmountRaised The total amount of ETH contributed during the sale.
     * @param softCapReached Whether the soft cap has been reached and the sale is successful.
     */
    event SaleEnded(uint256 totalAmountRaised, bool softCapReached);

    /**
     * @notice Initializes all the variables, mints the total supply and creates the vesting schedules.
     * @param _start The start date of the sale in unix timestamp.
     * @param _end The end date of the sale in unix timestamp.
     * @param _wallets The addresses of the project:
     * [0] = project wallet
     * [1] = team and adivsors address
     * [2] = marketing address
     * [3] = reserve fund address
     * [4] = development fund address
     * [5] = community incentives address
     */
    constructor(uint256 _start, uint256 _end, address[6] memory _wallets) ERC20("Zksyncpad", "Zksp") {
        vestingContract = new VestingContract(address(this));
        _mint(address(this), TOTAL_SUPPLY);

        // 15% of the sale expenses are unlocked at TGE
        _transfer(address(this), _wallets[0], TOKEN_SALE_EXPENSES * 15 / 100);
        // 20% of the marketing and partnerships tokens are unlocked at TGE
        _transfer(address(this), _wallets[2], (MARKETING_PARTNERSHIPS - BONUS_TOKENS) * 20 / 100);
        // 25% of the community incentives tokens are unlocked at TGE
        _transfer(address(this), _wallets[5], COMMUNITY * 25 / 100);

        // set up all the variables
        start = _start;
        end = _end;
        wallets = _wallets;
    }

    /**
     * @notice Initializes the vesting schedules.
     */
    function initializeVesting() external initializer {
        // 85% of the sale expenses are going to be vested monthly, for 12 months
        uint256 vestForSaleExpenses = TOKEN_SALE_EXPENSES * 85 / 100;
        _approve(address(this), address(vestingContract), vestForSaleExpenses);
        vestingContract.createVestingSchedule(
            wallets[0], block.timestamp, 12, VestingContract.DurationUnits.Months, vestForSaleExpenses
        );

        //100%  the team and advisors tokens are going to be vested monthly, for 24 months, after a 3 month cliff
        _approve(address(this), address(vestingContract), TEAM_ADVISORS);
        vestingContract.createVestingSchedule(
            wallets[1], block.timestamp + 3 * 30 days, 24, VestingContract.DurationUnits.Months, TEAM_ADVISORS
        );

        // 80% of the marketing and partnerships tokens are going to be vested monthly, for 12 months
        // the bonus is also given from the marketing and partnerships tokens
        uint256 vestForMarketing = (MARKETING_PARTNERSHIPS - BONUS_TOKENS) * 80 / 100;
        _approve(address(this), address(vestingContract), vestForMarketing);
        vestingContract.createVestingSchedule(
            wallets[2], block.timestamp, 12, VestingContract.DurationUnits.Months, vestForMarketing
        );

        // 100% of the reserve tokens are going to be vested monthly, for 12 months
        _approve(address(this), address(vestingContract), RESERVE);
        vestingContract.createVestingSchedule(
            wallets[3], block.timestamp, 12, VestingContract.DurationUnits.Months, RESERVE
        );

        // 100% of the development tokens are going to be vested monthly, for 12 months
        _approve(address(this), address(vestingContract), DEVELOPMENT);
        vestingContract.createVestingSchedule(
            wallets[4], block.timestamp, 12, VestingContract.DurationUnits.Months, DEVELOPMENT
        );

        // 75% of the community incentives tokens are going to be vested monthly, for 12 months
        uint256 vestForCommunity = COMMUNITY * 75 / 100;
        _approve(address(this), address(vestingContract), vestForCommunity);
        vestingContract.createVestingSchedule(
            wallets[5], block.timestamp, 12, VestingContract.DurationUnits.Months, vestForCommunity
        );
    }

    /**
     * @notice Buy tokens during the sale.
     */
    function buy() external payable {
        require(block.timestamp >= start, "Sale has not started yet");
        require(block.timestamp <= end, "Sale has ended");
        require(msg.value >= MINIMUM_BUY, "Amount of ETH sent is too low");
        require(msg.value <= MAXIMUM_BUY, "Amount of ETH sent is too high");

        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;

        if (contributors < 100 && eligibleForBonus[msg.sender] == 0) {
            eligibleForBonus[msg.sender] = msg.value;
            totalForBonus += msg.value;
        }

        emit EthContributed(msg.sender, msg.value);
    }

    /**
     * @notice User can claim their tokens after the sale has ended by calling this function, or the project can send the tokens to the user.
     */
    function airdrop(address[] calldata _buyers) external onlyOwner {
        require(saleEnded, "Sale has not ended yet");

        for (uint256 i = 0; i < _buyers.length; i++) {
            // if the user has no contribution, skip
            if (contributions[_buyers[i]] == 0) continue;
            // if the sale was successful, send the tokens
            if (softCapReached) {
                uint256 buyerContribution = contributions[_buyers[i]];

                // remove the contribution
                contributions[_buyers[i]] = 0;

                // if the total raised was over the hard cap, refund the user
                if (ethToRefund > 0) {
                    // calculate the amount of ETH to refund
                    uint256 amountToRefund = buyerContribution * ethToRefund / totalRaised;
                    (bool sc,) = _buyers[i].call{value: amountToRefund}("");
                    require(sc, "Refund failed");
                }

                // calculate the amount of tokens bought
                uint256 tokensBought = buyerContribution * PUBLIC_SALE / totalRaised;

                if (eligibleForBonus[_buyers[i]] > 0) {
                    // calculate the amount of bonus tokens to send
                    uint256 bonus = eligibleForBonus[_buyers[i]] * BONUS_TOKENS / totalForBonus;

                    tokensBought += bonus;
                }

                //send the tokens
                _transfer(address(this), _buyers[i], tokensBought);

                emit TokensClaimed(_buyers[i], tokensBought);
            } else {
                // else the sale was unsuccessful and the users are fully refunded
                uint256 amountToRefund = contributions[_buyers[i]];

                contributions[_buyers[i]] = 0;

                (bool sc,) = _buyers[i].call{value: amountToRefund}("");
                require(sc, "Refund failed");

                emit EthRefunded(_buyers[i], amountToRefund);
            }
        }
    }

    /**
     * @notice Ends the sale.
     * @dev If the soft cap has been reached, the liquidity is locked and the tokens are sent to the project wallet.
     */
    function endSale() external onlyOwner {
        require(block.timestamp > end, "Sale has not ended yet");
        require(!saleEnded, "Sale has already ended");

        // mark the sale as ended
        saleEnded = true;

        // if the soft cap has been reached, lock the liquidity and send the tokens to the project wallet
        if (totalRaised >= SOFT_CAP) {
            softCapReached = true;

            uint256 ethForProject = totalRaised;
            if (totalRaised > HARD_CAP) {
                ethToRefund = totalRaised - HARD_CAP;
                ethForProject = HARD_CAP;
            }
            (bool sc,) = payable(wallets[0]).call{value: ethForProject}("");
            require(sc, "Transfer failed");
        }

        emit SaleEnded(totalRaised, softCapReached);
    }
}
