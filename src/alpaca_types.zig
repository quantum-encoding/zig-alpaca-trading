// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");

/// Complete Alpaca API type definitions
/// Production-grade, feature-complete structures matching the official Alpaca API v2

/// Account status enumeration
pub const AccountStatus = enum {
    ONBOARDING,
    SUBMISSION_FAILED,
    SUBMITTED,
    ACCOUNT_UPDATED,
    APPROVAL_PENDING,
    ACTIVE,
    REJECTED,
    DISABLED,
    ACCOUNT_CLOSED,

    pub fn jsonStringify(self: AccountStatus, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Trading status enumeration
pub const TradingStatus = enum {
    ACTIVE,
    ACCOUNT_UPDATED,
    DISABLED,

    pub fn jsonStringify(self: TradingStatus, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Complete Account structure with all fields
pub const Account = struct {
    id: []const u8,
    account_number: []const u8,
    status: []const u8,
    crypto_status: ?[]const u8 = null,
    currency: []const u8,
    buying_power: []const u8,
    regt_buying_power: []const u8,
    daytrading_buying_power: []const u8,
    effective_buying_power: []const u8,
    non_marginable_buying_power: []const u8,
    bod_dtbp: []const u8,
    cash: []const u8,
    accrued_fees: []const u8,
    pending_transfer_in: ?[]const u8 = null,
    pending_transfer_out: ?[]const u8 = null,
    portfolio_value: []const u8,
    pattern_day_trader: bool,
    trading_blocked: bool,
    transfers_blocked: bool,
    account_blocked: bool,
    created_at: []const u8,
    trade_suspended_by_user: bool,
    multiplier: []const u8,
    shorting_enabled: bool,
    equity: []const u8,
    last_equity: []const u8,
    long_market_value: []const u8,
    short_market_value: []const u8,
    position_market_value: []const u8,
    initial_margin: []const u8,
    maintenance_margin: []const u8,
    last_maintenance_margin: []const u8,
    sma: []const u8,
    daytrade_count: i32,
    balance_asof: ?[]const u8 = null,
    crypto_tier: ?i32 = null,
    intraday_adjustments: ?[]const u8 = null,
    options_approved_level: ?i32 = null,
    options_buying_power: ?[]const u8 = null,
    options_trading_level: ?i32 = null,
};

/// Order side enumeration
pub const OrderSide = enum {
    buy,
    sell,

    pub fn jsonStringify(self: OrderSide, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Order type enumeration
pub const OrderType = enum {
    market,
    limit,
    stop,
    stop_limit,
    trailing_stop,

    pub fn jsonStringify(self: OrderType, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Time in force enumeration
pub const TimeInForce = enum {
    day,
    gtc,
    opg,
    cls,
    ioc,
    fok,

    pub fn jsonStringify(self: TimeInForce, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Order status enumeration
pub const OrderStatus = enum {
    @"new",
    partially_filled,
    filled,
    done_for_day,
    canceled,
    expired,
    replaced,
    pending_cancel,
    pending_replace,
    pending_new,
    accepted,
    accepted_for_bidding,
    stopped,
    rejected,
    suspended,
    calculated,

    pub fn jsonStringify(self: OrderStatus, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Order class enumeration
pub const OrderClass = enum {
    simple,
    bracket,
    oco,
    oto,

    pub fn jsonStringify(self: OrderClass, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Complete Order structure
pub const Order = struct {
    id: []const u8,
    client_order_id: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
    submitted_at: []const u8,
    filled_at: ?[]const u8 = null,
    expired_at: ?[]const u8 = null,
    canceled_at: ?[]const u8 = null,
    failed_at: ?[]const u8 = null,
    replaced_at: ?[]const u8 = null,
    replaced_by: ?[]const u8 = null,
    replaces: ?[]const u8 = null,
    asset_id: []const u8,
    symbol: []const u8,
    asset_class: []const u8,
    notional: ?[]const u8 = null,
    qty: ?[]const u8 = null,
    filled_qty: []const u8,
    filled_avg_price: ?[]const u8 = null,
    order_class: []const u8,
    order_type: []const u8,
    type: []const u8,
    side: []const u8,
    time_in_force: []const u8,
    limit_price: ?[]const u8 = null,
    stop_price: ?[]const u8 = null,
    status: []const u8,
    extended_hours: bool,
    legs: ?[]Order = null,
    trail_percent: ?[]const u8 = null,
    trail_price: ?[]const u8 = null,
    hwm: ?[]const u8 = null,
    subtag: ?[]const u8 = null,
    source: ?[]const u8 = null,
};

/// Complete Position structure
pub const Position = struct {
    asset_id: []const u8,
    symbol: []const u8,
    exchange: []const u8,
    asset_class: []const u8,
    asset_marginable: ?bool = null,
    qty: []const u8,
    avg_entry_price: []const u8,
    side: []const u8,
    market_value: []const u8,
    cost_basis: []const u8,
    unrealized_pl: []const u8,
    unrealized_plpc: []const u8,
    unrealized_intraday_pl: []const u8,
    unrealized_intraday_plpc: []const u8,
    current_price: []const u8,
    lastday_price: []const u8,
    change_today: []const u8,
    swap_rate: ?[]const u8 = null,
    avg_entry_swap_rate: ?[]const u8 = null,
    usd: ?PositionUSD = null,
    qty_available: []const u8,
};

/// Position USD values
pub const PositionUSD = struct {
    avg_entry_price: []const u8,
    market_value: []const u8,
    cost_basis: []const u8,
    unrealized_pl: []const u8,
    unrealized_plpc: []const u8,
    unrealized_intraday_pl: []const u8,
    unrealized_intraday_plpc: []const u8,
    current_price: []const u8,
    lastday_price: []const u8,
    change_today: []const u8,
};

/// Asset structure
pub const Asset = struct {
    id: []const u8,
    class: []const u8,
    exchange: []const u8,
    symbol: []const u8,
    name: []const u8,
    status: []const u8,
    tradable: bool,
    marginable: bool,
    maintenance_margin_requirement: ?f64 = null,
    shortable: bool,
    easy_to_borrow: bool,
    fractionable: bool,
    min_order_size: ?[]const u8 = null,
    min_trade_increment: ?[]const u8 = null,
    price_increment: ?[]const u8 = null,
    attributes: ?[][]const u8 = null,
};

/// Watchlist structure
pub const Watchlist = struct {
    id: []const u8,
    account_id: []const u8,
    name: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
    assets: ?[]Asset = null,
};

/// Clock structure
pub const Clock = struct {
    timestamp: []const u8,
    is_open: bool,
    next_open: []const u8,
    next_close: []const u8,
};

/// Calendar structure
pub const Calendar = struct {
    date: []const u8,
    open: []const u8,
    close: []const u8,
};

/// Bar structure for historical data
pub const Bar = struct {
    t: []const u8, // timestamp
    o: f64, // open
    h: f64, // high
    l: f64, // low
    c: f64, // close
    v: u64, // volume
    n: ?u64 = null, // number of trades
    vw: ?f64 = null, // volume weighted average price
};

/// Bars response
pub const BarsResponse = struct {
    bars: []Bar,
    symbol: []const u8,
    next_page_token: ?[]const u8 = null,
};

/// Quote structure
pub const Quote = struct {
    t: []const u8, // timestamp
    ax: []const u8, // ask exchange
    ap: f64, // ask price
    @"as": u64, // ask size
    bx: []const u8, // bid exchange
    bp: f64, // bid price
    bs: u64, // bid size
    c: [][]const u8, // conditions
    z: []const u8, // tape
};

/// Trade structure
pub const Trade = struct {
    t: []const u8, // timestamp
    x: []const u8, // exchange
    p: f64, // price
    s: u64, // size
    c: [][]const u8, // conditions
    i: u64, // trade id
    z: []const u8, // tape
};

/// Snapshot structure
pub const Snapshot = struct {
    symbol: []const u8,
    latestTrade: ?Trade = null,
    latestQuote: ?Quote = null,
    minuteBar: ?Bar = null,
    dailyBar: ?Bar = null,
    prevDailyBar: ?Bar = null,
};

/// Portfolio history structure
pub const PortfolioHistory = struct {
    timestamp: []i64,
    equity: []f64,
    profit_loss: []f64,
    profit_loss_pct: []f64,
    base_value: f64,
    base_value_asof: ?[]const u8 = null,
    timeframe: []const u8,
};

/// Announcement structure
pub const Announcement = struct {
    id: []const u8,
    corporate_action_id: []const u8,
    ca_type: []const u8,
    ca_sub_type: []const u8,
    initiating_symbol: []const u8,
    initiating_original_cusip: []const u8,
    target_symbol: ?[]const u8 = null,
    target_original_cusip: ?[]const u8 = null,
    declaration_date: []const u8,
    ex_date: ?[]const u8 = null,
    record_date: ?[]const u8 = null,
    payable_date: ?[]const u8 = null,
    cash: ?[]const u8 = null,
    old_rate: ?[]const u8 = null,
    new_rate: ?[]const u8 = null,
};

/// Configuration structure
pub const Configuration = struct {
    dtbp_check: []const u8,
    fragment_check: []const u8,
    trade_confirm_email: []const u8,
    suspend_trade: bool,
    no_shorting: bool,
    ptp_no_exception_entry: bool,
    max_margin_multiplier: []const u8,
    max_options_trading_level: ?i32 = null,
};

/// Activity type enumeration
pub const ActivityType = enum {
    FILL,
    TRANS,
    MISC,
    ACATC,
    ACATS,
    CSD,
    CSW,
    DIV,
    DIVCGL,
    DIVCGS,
    DIVFEE,
    DIVFT,
    DIVNRA,
    DIVROC,
    DIVTW,
    DIVTXEX,
    INT,
    INTNRA,
    INTTW,
    JNL,
    JNLC,
    JNLS,
    MA,
    NC,
    OPASN,
    OPEXP,
    OPXRC,
    PTC,
    PTR,
    REORG,
    SC,
    SSO,
    SSP,
    SPIN,
    SPL,
    FEE,

    pub fn jsonStringify(self: ActivityType, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Activity structure
pub const Activity = struct {
    activity_type: []const u8,
    id: []const u8,
    symbol: ?[]const u8 = null,
    transaction_time: []const u8,
    type: []const u8,
    price: ?[]const u8 = null,
    qty: ?[]const u8 = null,
    side: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    leaves_qty: ?[]const u8 = null,
    cum_qty: ?[]const u8 = null,
    net_amount: ?[]const u8 = null,
    per_share_amount: ?[]const u8 = null,
    description: ?[]const u8 = null,
    status: ?[]const u8 = null,
};