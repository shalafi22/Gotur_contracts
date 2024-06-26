// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <=0.9.0;

import "./FoodToken.sol";
import "./CustomerToken.sol";
import "./StoreToken.sol";
import "./CourierToken.sol";

contract Gotur {
    FoodToken public token;
    CourierToken public courierToken;
    CustomerToken public customerToken;
    StoreToken public storeToken;

    mapping(address => uint256) private balances;
    mapping(address => uint256) private stakes;

    mapping(address => Store) stores;
    address[] storeOwners;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    modifier isNotCustomer() {
        require(customerToken.balanceOf(msg.sender) == 0, "You are already registered as a customer!");
        _;
    }

    modifier isNotStore() {
        require(storeToken.balanceOf(msg.sender) == 0, "You are already registered as a store!");
        _;
    }

    modifier isNotCourier() {
        require(courierToken.balanceOf(msg.sender) == 0, "You are already registered as a courier!");
        _;
    }

    modifier isCustomer() {
        require(customerToken.balanceOf(msg.sender) == 1, "You are not registered as a customer!");
        _;
    }

    modifier isStore() {
        require(storeToken.balanceOf(msg.sender) == 1, "You are not registered as a store!");
        _;
    }

    modifier isCourier() {
        require(courierToken.balanceOf(msg.sender) == 1, "You are not registered as a courier!");
        _;
    }

    constructor(address token20, address courierT, address customerT, address storeT) {
        courierToken = CourierToken(courierT);
        customerToken = CustomerToken(customerT);
        storeToken = StoreToken(storeT);
        token = FoodToken(token20);
    }

    struct Item {
        string name;
        uint price;
        bool isAvailable;
        uint quantity;
    }

    struct Store {
        string name;
        address owner;
        mapping(uint => Item) items;
        uint nextItemId;
        bool isOpen;
        uint[] orders;
    }

    struct StoreRet {
        string name;
        address owner;
    }

    event newOrder(address store);
    event orderCanceled(address store, uint orderId);
    event orderApproved(address store, uint orderId);
    uint nextOrderId;
    Order[] orders;

    mapping(address => uint[]) orderHistory;

    //----------------------------Store and Item Functions-------------------------------

    function getMenu(address ownerAddr) public view returns (Item[] memory){
        Store storage store = stores[ownerAddr];
        Item[] memory ret = new Item[](store.nextItemId);
        for (uint i = 0; i < store.nextItemId; i++) {
            if (store.items[i].isAvailable) {
                ret[i] = store.items[i];
            }
        }
        return ret;
    }

    function addItem(string memory _name, uint _price, uint _quantity) public isStore {
        Store storage store = stores[msg.sender];
        require(store.owner == msg.sender, "Unauthorized");
        Item storage itm = store.items[store.nextItemId];
        itm.name = _name;
        itm.price = _price;
        itm.isAvailable = true;
        itm.quantity = _quantity;
        store.nextItemId += 1;
    }

    function setQuantity(uint itemId, uint _quantity) public isStore {
        require(_quantity >= 0, "Negative quantity not allowed");
        Store storage store = stores[msg.sender];
        require(store.owner == msg.sender, "Unauthorized");
        require(itemId < store.nextItemId, "Invalid itemId");
        Item storage itm = store.items[itemId];
        itm.quantity = _quantity;
    }

    function openStore() public isStore {
        Store storage store = stores[msg.sender];
        require(store.owner == msg.sender, "Unauthorized");
        store.isOpen = true;
    }

    function closeStore() public isStore {
        Store storage store = stores[msg.sender];
        require(store.owner == msg.sender, "Unauthorized");
        store.isOpen = false;
    }

    function disableItem(uint itemId) public isStore {
        Store storage store = stores[msg.sender];
        require(store.owner == msg.sender, "Unauthorized");
        require(itemId < store.nextItemId, "Invalid itemId");
        Item storage itm = store.items[itemId];
        itm.isAvailable = !itm.isAvailable;
    }

    
    //----------------------------Order Functions-------------------------

    struct Order {
        uint orderId;
        address customer;
        address store;
        address courier;
        uint totalPrice;
        uint courierFee;
        uint[] itemIds;
        uint[] quantitities;
        bool courierFound;
        bool storeApproved;
        bool courierPickedUp;
        bool isDeliveredByCourier;
        bool isReceivedByCustomer;
        bool isCanceled;
        bool isComplete;
        string mapAddress;
        uint issuetime;
        uint storeApproveTime;
    }
   

    function placeOrder(address storeAddress, uint[] memory _itemIds, uint[] memory _quantities, string memory _mapAddress, uint _courierFee, uint _totalPrice) public isNotStore isNotCourier {
        require(balances[msg.sender] >= _totalPrice + _courierFee, "Insufficient funds");
        require(stakes[storeAddress] >= _totalPrice, "Store doesn't have enough stake");
        Store storage store = stores[storeAddress];

        for (uint i = 0; i < _itemIds.length; i++) {
            if (!store.items[_itemIds[i]].isAvailable) {
                revert("Invalid or unavailable item!");
            } else if (store.items[_itemIds[i]].quantity < _quantities[i]) {
                revert("Too large quantity for item");
            }
        }
        Order memory order;
        order.customer = msg.sender;
        require(storeToken.balanceOf(storeAddress) == 1, "Invalid store address!");
        require(stores[storeAddress].isOpen, "Store is closed");
        order.store = storeAddress;
        order.courierFee = _courierFee;
        order.totalPrice = _totalPrice;
        order.issuetime = block.timestamp;
        order.itemIds = _itemIds;
        order.quantitities = _quantities;
        order.mapAddress = _mapAddress;
        order.orderId = nextOrderId;

        nextOrderId += 1;

        orders.push(order);
        orderHistory[msg.sender].push(order.orderId);
        orderHistory[storeAddress].push(order.orderId);

        for (uint i = 0; i < _itemIds.length; i++) {
            store.items[_itemIds[i]].quantity -= _quantities[_itemIds[i]];
        }

        balances[msg.sender] -= _totalPrice + _courierFee;

        emit newOrder(storeAddress);
        
    }

    function approveOrder(uint _orderId) public isStore {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.store == msg.sender, "Not your order");
        if (order.isCanceled) {
            revert("Order was canceled by the user");
        } else {
            order.storeApproved = true;
            order.storeApproveTime = block.timestamp;
            emit orderApproved(msg.sender, _orderId);
        }
        
    }

    function cancelOrder(uint _orderId) public isCustomer {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.customer == msg.sender, "Not your order");
        if (order.storeApproved) {
            revert("Store alreaady approved your order and is preparing!");
        } else {
            order.isCanceled = true;
            emit orderCanceled(order.store, _orderId);
        }
    }

    function takeOrderAsCourier(uint _orderId) public isCourier {
        //TODO: 
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.storeApproved && !order.courierFound && !order.isCanceled, "Order is not available");
        require(stakes[msg.sender] >= order.totalPrice + order.courierFee, "Not enough stake");

        order.courierFound = true;
        order.courier = msg.sender;
        
        orderHistory[msg.sender].push(order.orderId);
    }

    function markOrderPickedUp(uint _orderId) public isCourier {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];

        balances[order.store] += order.totalPrice;
        order.courierPickedUp = true;
    }

    function markOrderDelivered(uint _orderId) public isCourier {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.courier == msg.sender && order.courierPickedUp, "Order is not available");

        order.isDeliveredByCourier = true;
    }
    
    function markOrderReceived(uint _orderId) public isCustomer {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.customer == msg.sender && order.isDeliveredByCourier, "Order is not available");

        order.isReceivedByCustomer = true;
        order.isComplete = true;

        balances[order.courier] += order.courierFee;
    }

    function cancelOrderByTime(uint _orderId) public isCustomer {
        require(_orderId < nextOrderId, "Invalid orderID");
        Order storage order = orders[_orderId];
        require(order.customer == msg.sender && order.storeApproved && !order.isDeliveredByCourier, "Order is not available");
        require(block.timestamp >= order.issuetime + 30 seconds, "Too soon to cancel"); //DEBUG: change this to minutes
        if (!order.courierPickedUp) {
            order.isCanceled = true;
            balances[msg.sender] += 2 * order.totalPrice + order.courierFee;
            stakes[order.store] -= order.totalPrice;
        } else {
            order.isCanceled = true;
            balances[msg.sender] += 2 * order.courierFee;
            stakes[order.courier] -= order.courierFee;
        }
        
    }
    //--------------------------Getters-------------------------
    function getActiveOrders() external view returns (Order[] memory) {
        uint[] memory ids = orderHistory[msg.sender];
        

        uint activeCount = 0;
        for (uint i = 0; i < ids.length; i++) {
            if (!orders[ids[i]].isComplete && !orders[ids[i]].isCanceled) {
                activeCount++;
            }
        }

        Order[] memory ret = new Order[](activeCount);
        uint j = 0;
        for (uint i = 0; i < ids.length; i++) {
            if (!orders[ids[i]].isComplete && !orders[ids[i]].isCanceled) {
                ret[j] = orders[ids[i]];
                j += 1;
            }
        }
        return ret;
    }

    function getStores() public view returns (StoreRet[] memory) {
        StoreRet[] memory ret = new StoreRet[](storeOwners.length);
        for (uint i = 0; i < ret.length; i++) {
            if (stores[storeOwners[i]].isOpen) {
                ret[i] = StoreRet(stores[storeOwners[i]].name, stores[storeOwners[i]].owner);
            }
        }
        return ret;
    }

    function getServeableOrders() external isCourier view returns (Order[] memory) {
        //TODO: highly inefficient
        //return 10 orders at max...
        Order[] memory ret = new Order[](10);
        uint j = 0;
        for (uint i = 0; i < nextOrderId && j < 10; i++) {
            if (!orders[i].isCanceled && !orders[i].courierFound && orders[i].storeApproved) {
                ret[j] = orders[i];
                j += 1;
            }
        }   
        return ret;
    }

    function getItemFromStore(uint itemId, address storeAddress) public view returns (Item memory) {
        require(storeToken.balanceOf(storeAddress) == 1, "Invalid store address");
        Store storage store = stores[storeAddress];
        require(itemId < store.nextItemId, "Invalid itemID");
        return store.items[itemId];
    }

    function getCompletedOrders() external view returns (Order[] memory) {
        uint[] memory ids = orderHistory[msg.sender];
        Order[] memory ret = new Order[](ids.length);
        uint j = 0; 
        for (uint i = 0; i < ids.length; i++) {
            if (orders[ids[i]].isComplete) {
                ret[j] = orders[ids[i]];
                j += 1;
            }
        }
        return ret;
    }

    //---------------------------User Type Functions---------------------------

    function makeCustomer() public isNotCourier isNotStore{
        customerToken.safeMint(msg.sender);
    }

    function makeStore(string memory _name) public isNotCustomer isNotCourier {
        require(balances[msg.sender] >= 1000, "1000 FTK required to become a store!");
        storeToken.safeMint(msg.sender);
        stakes[msg.sender] += 1000;
        balances[msg.sender] -= 1000;

        stores[msg.sender].name = _name;
        stores[msg.sender].owner = msg.sender;
        stores[msg.sender].nextItemId = 0;
        storeOwners.push(msg.sender);
    }

    function makeCourier() public isNotCustomer isNotStore{
        require(balances[msg.sender] >= 500, "500 FTK required to becoma a courier");
        courierToken.safeMint(msg.sender);
        stakes[msg.sender] += 500;
        balances[msg.sender] -= 500;
    }

    //-------------------Token Functions-------------------------

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        balances[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        require(token.transfer(msg.sender, amount), "Token transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function placeStake(uint amount) public isNotCustomer {
        require(balances[msg.sender] >= amount, "Not enough funds");
        balances[msg.sender] -= amount;
        stakes[msg.sender] += amount;
    }

    function stakeOf(address user) external view returns (uint256) {
        return stakes[user];
    }
}