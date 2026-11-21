addon.name    = 'Zzloot';
addon.author  = 'Zanzah';
addon.version = 'v5.0';
addon.desc    = '/zzl help for info.';
addon.link    = 'Zanzah.com/donate';

require('common');
local chat     = require('chat');
local settings = require('settings');
local imgui    = require('imgui');
local ffi      = require('ffi');
local bitlib   = rawget(_G, 'bit');
local user32 = nil;
local has_get_async_key_state = false;
pcall(function ()
    ffi.cdef[[ short GetAsyncKeyState(int vKey); ]];
    user32 = ffi.load('user32');
    has_get_async_key_state = (user32 ~= nil and user32.GetAsyncKeyState ~= nil);
end);
if (bitlib == nil) then
    local ok_, mod = pcall(require, 'bit');
    if (ok_) then bitlib = mod; end
end
local bit = bitlib or rawget(_G, 'bit32');
local defaults = T{
    Lot       = T{},
    Pass      = T{},
    Drop      = T{},
    AutoStack = true,
    AutoDrop  = false,
    Delay     = 0,
    Verbose   = false,
    Enabled   = true,
    CurrentProfiles      = T{},
    ZoneProfiles         = T{},
    Auto                 = false,
    ProfilesInitialized  = false,
    IgnoreZones            = T{230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 26},
    IgnoreZonesInitialized = false,
    AirshipIgnoreZonesInitialized = false,
RuleUI = T{
    visible = false,
    x = 200,
    y = 200,
    w = 420,
    max_rows = 8,
    scale = 100,
    opacity = 100,
    minimized = false,
    needs_center = false,
},
};
local gSettings = settings.load(defaults);
local state = {};
local DEFAULT_IGNORE_ZONES = T{230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 26};
if (gSettings.IgnoreZones == nil and gSettings.PauseZones ~= nil) then
    gSettings.IgnoreZones = gSettings.PauseZones;
end
if (gSettings.IgnoreZonesInitialized == nil or gSettings.IgnoreZonesInitialized == false) then
    if (gSettings.IgnoreZones == nil or #gSettings.IgnoreZones == 0) then
        gSettings.IgnoreZones = T(DEFAULT_IGNORE_ZONES);
    end
    gSettings.IgnoreZonesInitialized = true;
    settings.save();
end
if (gSettings.CurrentProfiles == nil or type(gSettings.CurrentProfiles) ~= 'table') then
    gSettings.CurrentProfiles = T{};
    settings.save();
end
if (gSettings.ZoneProfiles == nil or type(gSettings.ZoneProfiles) ~= 'table') then
    gSettings.ZoneProfiles = T{};
    settings.save();
end
if (gSettings.RuleUI == nil or type(gSettings.RuleUI) ~= 'table') then
    gSettings.RuleUI = defaults.RuleUI;
    settings.save();
else
    local changed = false;
    if (gSettings.RuleUI.scale == nil) then
        gSettings.RuleUI.scale = 100;
        changed = true;
    end
    if (gSettings.RuleUI.opacity == nil) then
        gSettings.RuleUI.opacity = 100;
        changed = true;
    end
    local rule_ui_opacity = tonumber(gSettings.RuleUI.opacity) or 100;
    rule_ui_opacity = math.floor(rule_ui_opacity + 0.5);
    if (rule_ui_opacity < 30) then rule_ui_opacity = 30; end
    if (rule_ui_opacity > 100) then rule_ui_opacity = 100; end
    if (tonumber(gSettings.RuleUI.opacity) ~= rule_ui_opacity) then
        gSettings.RuleUI.opacity = rule_ui_opacity;
        changed = true;
    end
    if (gSettings.RuleUI.max_rows == nil) then
        gSettings.RuleUI.max_rows = 8;
        changed = true;
    end
    if (gSettings.RuleUI.minimized == nil) then
        gSettings.RuleUI.minimized = false;
        changed = true;
    end
    if (gSettings.RuleUI.needs_center ~= false) then
        gSettings.RuleUI.needs_center = false;
        changed = true;
    end
    if (changed) then
        settings.save();
    end
end
local function normalize_item_term(term)
    term = term or '';
    if (type(ParseAutoTranslate) == 'function') then
        term = ParseAutoTranslate(term, false) or term;
    end
    term = tostring(term);
    term = term:gsub('[%z\1-\31]', '');
    term = term:trim();
    term = term:gsub('^%s*<%s*(.-)%s*>%s*$', '%1');
    term = term:gsub('^%s*%[%s*(.-)%s*%]%s*$', '%1');
    term = term:gsub('^%s*"(.-)"%s*$', '%1');
    return term:trim();
end
local function normalize_profile_term(term)
    term = tostring(term or '');
    term = term:gsub('[%z\1-\31]', '');
    term = term:trim();
    term = term:gsub('^%s*<%s*(.-)%s*>%s*$', '%1');
    term = term:gsub('^%s*%[%s*(.-)%s*%]%s*$', '%1');
    term = term:gsub('^%s*"(.-)"%s*$', '%1');
    term = term:gsub('%.lua$', '');
    term = term:gsub('%s+', ' ');
    return term:trim();
end
local function validate_profile_name(raw)
    local name = normalize_profile_term(raw);
    if (name == '') then
        return nil, 'empty';
    end
    if (name:find('[\\/:*?"<>|]') ~= nil) then
        return nil, 'invalid_chars';
    end
    if (name:find('%.') ~= nil) then
        return nil, 'invalid_chars';
    end
    return name, nil;
end
local function try_get_item_by_name(rm, name)
    if (rm == nil or name == nil or name == '') then return nil; end
    for _,lang in ipairs({ 1, 2, 0, 3 }) do
        local it = rm:GetItemByName(name, lang);
        if (it ~= nil and it.ItemId ~= nil and tonumber(it.ItemId) ~= 0) then
            return it;
        end
    end
    return nil;
end
local compiled = {
    Lot  = {},
    Pass = {},
    Drop = {},
    IgnoreZones = {},
};
local function rebuild_compiled()
    compiled.Lot  = {};
    compiled.Pass = {};
    compiled.Drop = {};
    compiled.IgnoreZones = {};
    if (type(gSettings.Lot) == 'table') then
        for _,v in ipairs(gSettings.Lot) do compiled.Lot[tonumber(v) or 0] = true; end
    end
    if (type(gSettings.Pass) == 'table') then
        for _,v in ipairs(gSettings.Pass) do compiled.Pass[tonumber(v) or 0] = true; end
    end
    if (type(gSettings.Drop) == 'table') then
        for _,v in ipairs(gSettings.Drop) do compiled.Drop[tonumber(v) or 0] = true; end
    end
    local iz = gSettings.IgnoreZones or gSettings.PauseZones;
    if (type(iz) == 'table') then
        for _,v in ipairs(iz) do
            local zid = tonumber(v) or 0;
            if (zid ~= 0) then compiled.IgnoreZones[zid] = true; end
        end
    end
end
local function request_autodrop_rescan()
    if (gSettings.AutoDrop ~= true) then return false; end
    if (compiled.Drop == nil or next(compiled.Drop) == nil) then return false; end
    state.inv_dirty = true;
    return true;
end
local function invalidate_rule_ui_cache()
    if (state == nil or type(state) ~= 'table') then
        return;
    end
    state.rule_ui_cache_dirty = true;
end
local function mark_unsaved_runtime_changes(reason)
    if (state == nil or type(state) ~= 'table') then
        return;
    end
    state.runtime_profile_dirty = true;
    state.runtime_profile_dirty_reason = tostring(reason or '');
end
local function clear_unsaved_runtime_changes()
    if (state == nil or type(state) ~= 'table') then
        return;
    end
    state.runtime_profile_dirty = false;
    state.runtime_profile_dirty_reason = nil;
end
local function mark_rule_ui_recent_ids(ids)
    if (state == nil or type(state) ~= 'table') then
        return;
    end
    state.rule_ui_recent_order = state.rule_ui_recent_order or {};
    state.rule_ui_recent_seq = tonumber(state.rule_ui_recent_seq) or 0;
    local seen = {};
    for _,v in ipairs(ids or {}) do
        local id = tonumber(v) or 0;
        if (id ~= 0 and not seen[id]) then
            seen[id] = true;
            state.rule_ui_recent_seq = state.rule_ui_recent_seq + 1;
            state.rule_ui_recent_order[id] = state.rule_ui_recent_seq;
        end
    end
end
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        gSettings = s;
    end
    if (state ~= nil and type(state) == 'table') then
        state.current_profile_zone_id = -1;
        state.lot_skip_notified = {};
        state.lot_rejected_current_pool = {};
        state.recent_lot_attempts = {};
        state.deferred_warns = {};
        state.actions = {};
        state.inv_dirty = false;
        state.drop_pending = false;
        state.pool_empty_since = os.clock();
        for i = 0, 9 do
            if (state.pool_ids ~= nil) then state.pool_ids[i] = 0; end
            if (state.pool_status ~= nil) then state.pool_status[i] = 0; end
        end
    end
    rebuild_compiled();
    invalidate_rule_ui_cache();
    pcall(function() sync_zone_profile_state(true); end);
    settings.save();
end);
local function get_memory_manager()
    if (AshitaCore == nil or AshitaCore.GetMemoryManager == nil) then return nil; end
    local ok, mm = pcall(function () return AshitaCore:GetMemoryManager(); end);
    if (not ok) then return nil; end
    return mm;
end
local function get_data_manager()
    if (AshitaCore == nil or AshitaCore.GetDataManager == nil) then return nil; end
    local ok, dm = pcall(function () return AshitaCore:GetDataManager(); end);
    if (not ok) then return nil; end
    return dm;
end
local function get_party_manager()
    local mm = get_memory_manager();
    if (mm ~= nil and mm.GetParty ~= nil) then
        local p = mm:GetParty();
        if (p ~= nil) then return p; end
    end
    local dm = get_data_manager();
    if (dm ~= nil and dm.GetParty ~= nil) then
        return dm:GetParty();
    end
    return nil;
end
local function get_inventory_manager()
    local mm = get_memory_manager();
    if (mm ~= nil and mm.GetInventory ~= nil) then
        local inv = mm:GetInventory();
        if (inv ~= nil) then return inv; end
    end
    local dm = get_data_manager();
    if (dm ~= nil and dm.GetInventory ~= nil) then
        return dm:GetInventory();
    end
    return nil;
end
local function inventory_get_container_max(inv, bag)
    if (inv == nil) then return nil; end
    if (inv.GetContainerCountMax ~= nil) then return inv:GetContainerCountMax(bag); end
    if (inv.GetContainerMax ~= nil) then return inv:GetContainerMax(bag); end
    return nil;
end
local function inventory_get_container_count(inv, bag)
    if (inv == nil) then return nil; end
    if (inv.GetContainerCount ~= nil) then return inv:GetContainerCount(bag); end
    return nil;
end
local function inventory_get_item(inv, bag, index)
    if (inv == nil) then return nil; end
    if (inv.GetContainerItem ~= nil) then return inv:GetContainerItem(bag, index); end
    if (inv.GetItem ~= nil) then return inv:GetItem(bag, index); end
    return nil;
end
local function get_current_zone_id()
    local zid = nil;
    local p = get_party_manager();
    if (p ~= nil and p.GetMemberZone ~= nil) then
        zid = p:GetMemberZone(0);
    end
    zid = tonumber(zid) or 0;
    if (zid <= 0) then return nil; end
    return zid;
end
local function is_player_logged_in()
    local mm = get_memory_manager();
    local party = (mm ~= nil and mm.GetParty ~= nil) and mm:GetParty() or nil;
    local player_index = (party ~= nil and party.GetMemberTargetIndex ~= nil) and tonumber(party:GetMemberTargetIndex(0)) or 0;
    if (player_index == nil or player_index == 0) then
        return false;
    end
    local entity = (mm ~= nil and mm.GetEntity ~= nil) and mm:GetEntity() or nil;
    if (entity == nil or entity.GetRenderFlags0 == nil or bit == nil) then
        return true;
    end
    local flags = tonumber(entity:GetRenderFlags0(player_index)) or 0;
    return bit.band(flags, 0x200) == 0x200 and bit.band(flags, 0x4000) == 0;
end
local function is_ignored_zone()
    local zid = get_current_zone_id();
    if (zid == nil) then return false; end
    return compiled.IgnoreZones[zid] == true;
end
local function is_active()
    if (gSettings.Enabled == false) then return false; end
    if (is_ignored_zone()) then return false; end
    return true;
end
math.randomseed(os.time());
local function warn(msg)
    print(chat.header(addon.name):append(chat.warning(msg)));
end
local function msg(msg)
    print(chat.header(addon.name):append(chat.message(msg)));
end
local function ok(msg_)
    print(chat.header(addon.name):append(chat.success(msg_)));
end
local function err(msg_)
    print(chat.header(addon.name):append(chat.error(msg_)));
end
local function echo(msg_)
    msg_ = tostring(msg_ or '');
    local cm = (AshitaCore ~= nil and AshitaCore.GetChatManager ~= nil) and AshitaCore:GetChatManager() or nil;
    if (cm ~= nil) then
        local ok_ = pcall(function()
            cm:QueueCommand(-1, '/echo ' .. msg_);
        end);
        if (not ok_) then
            ok_ = pcall(function()
                cm:QueueCommand(1, '/echo ' .. msg_);
            end);
        end
        if (not ok_) then
            ok_ = pcall(function()
                cm:QueueCommand('/echo ' .. msg_, -1);
            end);
        end
        if (not ok_) then
            ok_ = pcall(function()
                cm:QueueCommand('/echo ' .. msg_, 1);
            end);
        end
        if (ok_) then
            return;
        end
    end
    msg(msg_);
end
local function verbose_msg(msg_)
    if (gSettings == nil or gSettings.Verbose ~= true) then
        return;
    end
    msg(msg_);
end
local function file_exists(path)
    local f = io.open(path, 'r');
    if (f ~= nil) then f:close(); return true; end
    return false;
end
local function bool_from_arg(s)
    if (s == nil) then return nil; end
    s = tostring(s):lower();
    if (s == 'on' or s == 'true' or s == '1' or s == 'yes') then return true; end
    if (s == 'off' or s == 'false' or s == '0' or s == 'no') then return false; end
    return nil;
end
local function remove_ids(list, ids)
    local to_remove = {};
    for _,id in ipairs(ids) do to_remove[tonumber(id) or 0] = true; end
    local out = {};
    for _,v in ipairs(list) do
        local n = tonumber(v) or 0;
        if (n ~= 0 and not to_remove[n]) then table.insert(out, n); end
    end
    return out;
end
local function get_item_name(id)
    local rm = AshitaCore:GetResourceManager();
    local it = rm and rm:GetItemById(tonumber(id) or 0) or nil;
    if (it ~= nil and it.Name ~= nil) then
        for _,idx in ipairs({ 1, 0, 2, 3 }) do
            local n = it.Name[idx];
            if (n ~= nil and tostring(n) ~= '') then
                return tostring(n);
            end
        end
    end
    return string.format('ItemId:%d', tonumber(id) or 0);
end
local function rule_name_upper(which)
    which = tostring(which or ''):lower();
    if (which == 'lot') then return 'LOT'; end
    if (which == 'pass') then return 'PASS'; end
    if (which == 'drop') then return 'DROP'; end
    return string.upper(tostring(which or ''));
end
local function set_to_sorted_id_list(set)
    local out = {};
    for id, on in pairs(set or {}) do
        id = tonumber(id) or 0;
        if (on == true and id ~= 0) then
            table.insert(out, id);
        end
    end
    table.sort(out, function(a, b)
        local an = tostring(get_item_name(a)):lower();
        local bn = tostring(get_item_name(b)):lower();
        if (an == bn) then
            return (tonumber(a) or 0) < (tonumber(b) or 0);
        end
        return an < bn;
    end);
    return out;
end
local function get_zone_name(zid)
    zid = tonumber(zid) or 0;
    if (zid == 0) then return nil; end
    local rm = (AshitaCore and AshitaCore.GetResourceManager) and AshitaCore:GetResourceManager() or nil;
    if (rm ~= nil) then
        if (rm.GetString ~= nil) then
            local ok_, s = pcall(function()
                return rm:GetString('zones.names', zid);
            end);
            if (ok_ and s ~= nil and tostring(s) ~= '') then
                return tostring(s);
            end
            ok_, s = pcall(function()
                return rm:GetString('zones', zid);
            end);
            if (ok_ and s ~= nil and tostring(s) ~= '') then
                return tostring(s);
            end
        end
        if (rm.GetZoneById ~= nil) then
            local z = rm:GetZoneById(zid);
            if (z ~= nil and z.Name ~= nil) then
                for _,idx in ipairs({ 1, 0, 2, 3 }) do
                    local n = z.Name[idx];
                    if (n ~= nil and tostring(n) ~= '') then
                        return tostring(n);
                    end
                end
            end
        end
    end
    return nil;
end
local function is_airship_zone_name(name)
    name = tostring(name or ''):lower();
    return (name ~= '' and name:find('airship', 1, true) ~= nil);
end
local function seed_default_airship_ignore_zones()
    if (gSettings == nil) then
        return;
    end
    if (gSettings.AirshipIgnoreZonesInitialized == true) then
        return;
    end
    gSettings.IgnoreZones = gSettings.IgnoreZones or T{};
    local seen = {};
    for _,v in ipairs(gSettings.IgnoreZones) do
        local zid = tonumber(v) or 0;
        if (zid ~= 0) then
            seen[zid] = true;
        end
    end
    for zid = 1, 300 do
        local zn = get_zone_name(zid);
        if (is_airship_zone_name(zn) and not seen[zid]) then
            table.insert(gSettings.IgnoreZones, zid);
            seen[zid] = true;
        end
    end
    table.sort(gSettings.IgnoreZones, function (a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0);
    end);
    gSettings.AirshipIgnoreZonesInitialized = true;
    settings.save();
end
local function sort_ids_by_name(list)
    list = list or {};
    local arr = {};
    local seen = {};
    for _,v in ipairs(list) do
        local id = tonumber(v) or 0;
        if (id ~= 0 and not seen[id]) then
            seen[id] = true;
            table.insert(arr, id);
        end
    end
    table.sort(arr, function(a,b)
        return tostring(get_item_name(a)):lower() < tostring(get_item_name(b)):lower();
    end);
    return arr;
end
local function get_rule_sort_rank(rule)
    rule = tostring(rule or ''):upper();
    if (rule == 'LOT') then return 1; end
    if (rule == 'PASS') then return 2; end
    if (rule == 'DROP') then return 3; end
    return 9;
end
local function build_rule_rows()
    local map = {};
    local function add_rule(list, key)
        if (type(list) ~= 'table') then return; end
        for _,v in ipairs(list) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then
                map[id] = map[id] or { L=false, P=false, D=false };
                map[id][key] = true;
            end
        end
    end
    add_rule(gSettings.Lot,  'L');
    add_rule(gSettings.Pass, 'P');
    add_rule(gSettings.Drop, 'D');
    local rows = {};
    for id,r in pairs(map) do
        local flags = {};
        if (r.L) then table.insert(flags, 'LOT'); end
        if (r.P) then table.insert(flags, 'PASS'); end
        if (r.D) then table.insert(flags, 'DROP'); end
        local rule = '(?)';
        if (#flags == 1) then
            rule = flags[1];
        else
            rule = 'CONFLICT:' .. table.concat(flags, '+');
        end
        table.insert(rows, { id = id, name = get_item_name(id), rule = rule });
    end
    local sort_mode = tostring((state and state.rule_ui_sort_mode) or 'alpha');
    local recent_order = (state and state.rule_ui_recent_order) or {};
    table.sort(rows, function(a,b)
        if (sort_mode == 'recent') then
            local ao = tonumber(recent_order[tonumber(a.id) or 0]) or 0;
            local bo = tonumber(recent_order[tonumber(b.id) or 0]) or 0;
            if (ao ~= bo) then
                return ao > bo;
            end
        else
            local ar = get_rule_sort_rank(a.rule);
            local br = get_rule_sort_rank(b.rule);
            if (ar ~= br) then
                return ar < br;
            end
        end
        local an = tostring(a.name or ''):lower();
        local bn = tostring(b.name or ''):lower();
        if (an == bn) then
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0);
        end
        return an < bn;
    end);
    return rows;
end
local function format_rule_ui_item_count(item_count)
    item_count = tonumber(item_count) or 0;
    if (item_count <= 0) then
        return '';
    end
    return string.format(' (%d item%s listed)', item_count, (item_count == 1) and '' or 's');
end
local function format_rule_ui_zone_title(zone_name, zone_id, ignored, item_count)
    zone_name = tostring(zone_name or 'Unknown Zone');
    zone_id = tonumber(zone_id) or 0;
    local out = string.format('%s [%d]', zone_name, zone_id);
    if (ignored == true) then
        out = out .. ' (ignored)';
    end
    out = out .. format_rule_ui_item_count(item_count);
    return out;
end
local function get_rule_ui_text_width(text, line_h)
    text = tostring(text or '');
    if (text == '') then
        return 0;
    end
    if (imgui.CalcTextSize ~= nil) then
        local ok_, a, b = pcall(function () return imgui.CalcTextSize(text); end);
        if (ok_) then
            if (type(a) == 'number' and a > 0) then
                return tonumber(a) or 0;
            end
            local x = tonumber(a and a[1]) or tonumber(a and a.x) or tonumber(a and a.X);
            if (x ~= nil and x > 0) then
                return x;
            end
        end
    end
    local approx_char_w = math.max(6, math.floor(((tonumber(line_h) or 14) * 0.55) + 0.5));
    return #text * approx_char_w;
end
local function vec2_xy(v)
    if (v == nil) then return nil, nil; end
    local function safe_get(obj, key)
        local ok_, value = pcall(function() return obj[key]; end);
        if (ok_) then return value; end
        return nil;
    end
    local x = tonumber(safe_get(v, 1));
    local y = tonumber(safe_get(v, 2));
    if (x ~= nil and y ~= nil) then
        return x, y;
    end
    if (x == nil) then x = tonumber(safe_get(v, 'x')) or tonumber(safe_get(v, 'X')); end
    if (y == nil) then y = tonumber(safe_get(v, 'y')) or tonumber(safe_get(v, 'Y')); end
    return x, y;
end
local function get_display_size()
    if (imgui.GetIO ~= nil) then
        local io = imgui.GetIO();
        if (io ~= nil) then
            local ds = io.DisplaySize;
            if (ds ~= nil) then
                local w, h = vec2_xy(ds);
                if (w ~= nil and h ~= nil) then
                    return w, h;
                end
            end
        end
    end
    if (imgui.GetMainViewport ~= nil) then
        local vp = imgui.GetMainViewport();
        if (vp ~= nil and vp.Size ~= nil) then
            local sz = vp.Size;
            local w, h = vec2_xy(sz);
            if (w ~= nil and h ~= nil) then
                return w, h;
            end
        end
    end
    return nil, nil;
end
local function reset_rule_ui_pos()
    gSettings.RuleUI.x = 0;
    gSettings.RuleUI.y = 0;
end
local function validate_rule_ui_saved_pos(win_w, approx_h)
    local dw, dh = get_display_size();
    if (dw == nil or dh == nil) then
        return false;
    end
    local x = tonumber(gSettings.RuleUI.x) or 0;
    local y = tonumber(gSettings.RuleUI.y) or 0;
    approx_h = approx_h or 260;
    win_w = win_w or (tonumber(gSettings.RuleUI.w) or 420);
    local title_h = tonumber(state.rule_ui_rect and state.rule_ui_rect.title_h) or math.max(18, math.min(tonumber(approx_h) or 24, 36));
    local reachable_w = math.min(tonumber(win_w) or 420, 140);
    if (y < 0 or y > (dh - title_h) or (x + reachable_w) < 0 or x > (dw - 40)) then
        reset_rule_ui_pos();
        return true;
    end
    return false;
end
local function apply_rule_ui_saved_pos_once(win_w, approx_h)
    if (state.rule_ui_apply_saved_pos ~= true) then
        return;
    end
    state.rule_ui_apply_saved_pos = false;
    if (gSettings.RuleUI.needs_center == true) then
        gSettings.RuleUI.needs_center = false;
        settings.save();
    end
    if (validate_rule_ui_saved_pos(win_w, approx_h)) then
        settings.save();
    end
end
local function set_next_rule_ui_pos(x, y)
    local ok_ = pcall(function ()
        imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    end);
    if (not ok_) then
        imgui.SetNextWindowPos({ x, y });
    end
end
local function set_next_rule_ui_size(w, h)
    local ok_ = pcall(function ()
        imgui.SetNextWindowSize({ w, h }, ImGuiCond_Always);
    end);
    if (not ok_) then
        imgui.SetNextWindowSize({ w, h });
    end
end
local function rule_ui_mark_pos_dirty(now)
    state.last_ui_save = state.last_ui_save or 0;
    if ((now - state.last_ui_save) > 0.20) then
        settings.save();
        state.last_ui_save = now;
    end
end
local function rule_ui_title_hit_test(x, y)
    if (gSettings.RuleUI == nil or gSettings.RuleUI.visible ~= true) then
        return false;
    end
    local rect = state.rule_ui_rect;
    if (rect == nil) then
        return false;
    end
    return (x >= rect.x and x <= (rect.x + rect.w) and y >= rect.y and y <= (rect.y + rect.title_h));
end
local function rect_contains(rect, x, y)
    if (rect == nil) then return false; end
    return (x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2);
end
local function clear_rule_ui_interactive_rects()
    state.rule_ui_interactive = {
        min_button = nil,
        close_button = nil,
        scrollbar = nil,
        child_area = nil,
    };
end
local function set_rule_ui_rect(name, x1, y1, x2, y2)
    state.rule_ui_interactive = state.rule_ui_interactive or {};
    state.rule_ui_interactive[name] = {
        x1 = math.floor((tonumber(x1) or 0) + 0.5),
        y1 = math.floor((tonumber(y1) or 0) + 0.5),
        x2 = math.floor((tonumber(x2) or 0) + 0.5),
        y2 = math.floor((tonumber(y2) or 0) + 0.5),
    };
end
local function rule_ui_hits_button(x, y)
    local ir = state.rule_ui_interactive;
    if (ir == nil) then return false; end
    return rect_contains(ir.min_button, x, y) or rect_contains(ir.close_button, x, y);
end
local function rule_ui_hits_scrollbar(x, y)
    local ir = state.rule_ui_interactive;
    if (ir == nil) then return false; end
    return rect_contains(ir.scrollbar, x, y);
end
local function rule_ui_hits_child_area(x, y)
    local ir = state.rule_ui_interactive;
    if (ir == nil) then return false; end
    return rect_contains(ir.child_area, x, y);
end
local function rule_ui_hits_window(x, y)
    local rect = state.rule_ui_rect;
    if (rect == nil) then return false; end
    local rx = tonumber(rect.x);
    local ry = tonumber(rect.y);
    local rw = tonumber(rect.w);
    local rh = tonumber(rect.h);
    if (rx == nil or ry == nil or rw == nil or rh == nil) then
        return false;
    end
    return (x >= rx and x <= (rx + rw) and y >= ry and y <= (ry + rh));
end
local function rule_ui_buttons_reachable()
    local dw, dh = get_display_size();
    if (dw == nil or dh == nil) then
        return true;
    end
    local ir = state.rule_ui_interactive or {};
    local header = state.rule_ui_rect;
    local title_h = tonumber(header and header.title_h) or 0;
    local right_x1 = nil;
    local right_y1 = nil;
    local right_x2 = nil;
    local right_y2 = nil;
    if (ir.close_button ~= nil) then
        right_x1 = tonumber(ir.close_button.x1);
        right_y1 = tonumber(ir.close_button.y1);
        right_x2 = tonumber(ir.close_button.x2);
        right_y2 = tonumber(ir.close_button.y2);
    elseif (ir.min_button ~= nil) then
        right_x1 = tonumber(ir.min_button.x1);
        right_y1 = tonumber(ir.min_button.y1);
        right_x2 = tonumber(ir.min_button.x2);
        right_y2 = tonumber(ir.min_button.y2);
    end
    if (right_x1 ~= nil and right_y1 ~= nil and right_x2 ~= nil and right_y2 ~= nil) then
        return not (right_x2 < 0 or right_x1 > dw or right_y2 < 0 or right_y1 > dh);
    end
    local x = tonumber(gSettings.RuleUI and gSettings.RuleUI.x) or 0;
    local y = tonumber(gSettings.RuleUI and gSettings.RuleUI.y) or 0;
    local w = tonumber(gSettings.RuleUI and gSettings.RuleUI.w) or 420;
    local reachable_w = math.min(math.max(64, w), 96);
    local right_x = x + w - reachable_w;
    local right_y = y;
    local right_x2_fallback = x + w;
    local right_y2_fallback = y + math.max(18, title_h);
    return not (right_x2_fallback < 0 or right_x > dw or right_y2_fallback < 0 or right_y > dh);
end
local function rule_ui_recover_if_buttons_unreachable(shift_down, left_down)
    if (shift_down ~= true or left_down == true) then
        state.rule_ui_recover_unreachable_since = nil;
        return false;
    end
    if (state.rule_ui_dragging == true) then
        state.rule_ui_recover_unreachable_since = nil;
        return false;
    end
    if (gSettings.RuleUI == nil or gSettings.RuleUI.visible ~= true) then
        state.rule_ui_recover_unreachable_since = nil;
        return false;
    end
    if (rule_ui_buttons_reachable()) then
        state.rule_ui_recover_unreachable_since = nil;
        return false;
    end
    local now = os.clock();
    if (state.rule_ui_recover_unreachable_since == nil) then
        state.rule_ui_recover_unreachable_since = now;
        return false;
    end
    if ((now - state.rule_ui_recover_unreachable_since) < 2.0) then
        return false;
    end
    state.rule_ui_recover_unreachable_since = nil;
    reset_rule_ui_pos();
    state.rule_ui_apply_saved_pos = true;
    state.rule_ui_dragging = false;
    state.rule_ui_button_capture = nil;
    settings.save();
    return true;
end
local function query_shift_state()
    if (has_get_async_key_state and user32 ~= nil and bit ~= nil) then
        local ok_, down = pcall(function ()
            local vk_shift  = bit.band(tonumber(user32.GetAsyncKeyState(0x10)) or 0, 0x8000) ~= 0;
            local vk_lshift = bit.band(tonumber(user32.GetAsyncKeyState(0xA0)) or 0, 0x8000) ~= 0;
            local vk_rshift = bit.band(tonumber(user32.GetAsyncKeyState(0xA1)) or 0, 0x8000) ~= 0;
            return vk_shift or vk_lshift or vk_rshift;
        end);
        if (ok_) then
            return down == true;
        end
    end
    return state.shift_down == true;
end
local function query_left_mouse_state()
    if (has_get_async_key_state and user32 ~= nil and bit ~= nil) then
        local ok_, down = pcall(function ()
            return bit.band(tonumber(user32.GetAsyncKeyState(0x01)) or 0, 0x8000) ~= 0;
        end);
        if (ok_) then
            return down == true;
        end
    end
    return state.left_mouse_down == true;
end
local function ensure_rule_ui_state()
    if (gSettings.RuleUI == nil or type(gSettings.RuleUI) ~= 'table') then
        gSettings.RuleUI = T(defaults.RuleUI);
    end
    if (gSettings.RuleUI.visible == nil) then gSettings.RuleUI.visible = false; end
    if (gSettings.RuleUI.scale == nil) then gSettings.RuleUI.scale = 100; end
    if (gSettings.RuleUI.opacity == nil) then gSettings.RuleUI.opacity = 100; end
    if (gSettings.RuleUI.max_rows == nil) then gSettings.RuleUI.max_rows = 8; end
    local rule_ui_opacity = math.floor((tonumber(gSettings.RuleUI.opacity) or 100) + 0.5);
    if (rule_ui_opacity < 30) then rule_ui_opacity = 30; end
    if (rule_ui_opacity > 100) then rule_ui_opacity = 100; end
    gSettings.RuleUI.opacity = rule_ui_opacity;
    if (gSettings.RuleUI.minimized == nil) then gSettings.RuleUI.minimized = false; end
    local saved_rule_ui_visible = (gSettings.RuleUI.visible == true);
    if (state.rule_ui_open == nil) then
        state.rule_ui_open = { saved_rule_ui_visible };
    else
        state.rule_ui_open[1] = saved_rule_ui_visible;
    end
    if (state.rule_ui_apply_saved_pos == nil) then state.rule_ui_apply_saved_pos = true; end
    if (state.rule_ui_cache_dirty == nil) then state.rule_ui_cache_dirty = true; end
    if (state.rule_ui_cache == nil) then state.rule_ui_cache = { zone_id = -1, zone_title = '', rows = T{}, show_scrollbar = false }; end
    if (state.rule_ui_scroll_step == nil) then state.rule_ui_scroll_step = 48; end
    if (state.rule_ui_has_scrollbar == nil) then state.rule_ui_has_scrollbar = false; end
    if (state.rule_ui_session_max_rows == nil) then state.rule_ui_session_max_rows = nil; end
    if (state.rule_ui_sort_mode == nil) then state.rule_ui_sort_mode = 'alpha'; end
    if (state.rule_ui_recent_order == nil) then state.rule_ui_recent_order = {}; end
    if (state.rule_ui_recent_seq == nil) then state.rule_ui_recent_seq = 0; end
end

local function reset_rule_ui_session_state()
    ensure_rule_ui_state();
    state.rule_ui_session_max_rows = nil;
    state.rule_ui_sort_mode = 'alpha';
    state.rule_ui_scroll_y = 0;
    state.rule_ui_pending_wheel = 0;
    state.rule_ui_recent_order = {};
    state.rule_ui_recent_seq = 0;
    invalidate_rule_ui_cache();
end

local function get_effective_rule_ui_max_rows()
    ensure_rule_ui_state();
    local max_rows = tonumber(state.rule_ui_session_max_rows);
    if (max_rows == nil) then
        max_rows = tonumber(gSettings.RuleUI.max_rows) or 8;
    end
    max_rows = math.floor((tonumber(max_rows) or 8) + 0.5);
    if (max_rows < 3) then max_rows = 3; end
    if (max_rows > 99) then max_rows = 99; end
    return max_rows;
end
local function set_rule_ui_visible(v)
    ensure_rule_ui_state();
    v = (v == true);
    state.rule_ui_open[1] = v;
    gSettings.RuleUI.visible = v;
    if (v) then
        state.rule_ui_apply_saved_pos = true;
        invalidate_rule_ui_cache();
    end
    settings.save();
end
local function toggle_rule_ui_visible()
    ensure_rule_ui_state();
    set_rule_ui_visible(not state.rule_ui_open[1]);
    return state.rule_ui_open[1];
end
local profile_files_string;
local persist_runtime_state_quiet;

local function get_rule_ui_base_line_height()
    local base = 14;
    if (imgui.GetTextLineHeightWithSpacing ~= nil) then
        local ok_, lh = pcall(function () return imgui.GetTextLineHeightWithSpacing(); end);
        if (ok_ and lh ~= nil and tonumber(lh) ~= nil and tonumber(lh) > 0) then
            base = tonumber(lh) or base;
        end
    end
    if (base < 12) then base = 12; end
    return base;
end
local function estimate_rule_ui_base_width(cache)
    local longest = 0;
    local function take_len(txt, extra)
        txt = tostring(txt or '');
        local n = #txt + (extra or 0);
        if (n > longest) then longest = n; end
    end
    take_len(cache and cache.zone_title or '', 10);
    take_len(cache and cache.profiles_text or '', 4);
    local rows = (cache and cache.rows) or T{};
    local longest_name = 0;
    local longest_id = 0;
    for _,r in ipairs(rows) do
        local rn = tostring((r and r.name) or '');
        local rid = tostring((r and r.id) or '');
        if (#rn > longest_name) then longest_name = #rn; end
        if (#rid > longest_id) then longest_id = #rid; end
        take_len((r and r.rule) or '', 2);
        take_len(string.format('%-12s %s %s', (r and r.rule) or '', rn, rid), 4);
    end
    if (longest_name > 0 or longest_id > 0) then
        take_len(string.rep('W', 12) .. ' ' .. string.rep('W', longest_name) .. ' ' .. string.rep('9', longest_id), 6);
    end
    if (longest < 36) then longest = 36; end
    local base_w = math.floor((longest * 8) + 34 + 0.5);
    if (base_w < 420) then base_w = 420; end
    if (base_w > 1100) then base_w = 1100; end
    return base_w;
end

local function refresh_rule_ui_cache(max_rows)
    ensure_rule_ui_state();
    local zid = get_current_zone_id() or 0;
    if (state.rule_ui_last_zone_id ~= zid) then
        state.rule_ui_last_zone_id = zid;
        state.rule_ui_cache_dirty = true;
        state.rule_ui_scroll_y = 0;
        state.rule_ui_pending_wheel = 0;
    end
    local function sig_for(list)
        if (type(list) ~= 'table') then return ''; end
        local parts = {};
        for _,v in ipairs(list) do
            parts[#parts + 1] = tostring(tonumber(v) or 0);
        end
        return table.concat(parts, ',');
    end
    local rule_sig = table.concat({ sig_for(gSettings.Lot), sig_for(gSettings.Pass), sig_for(gSettings.Drop), sig_for(gSettings.IgnoreZones) }, '|');
    local profile_sig = '';
    if (type(gSettings.CurrentProfiles) == 'table') then
        profile_sig = table.concat(gSettings.CurrentProfiles, ',');
    end
    if (state.rule_ui_rule_sig ~= rule_sig or state.rule_ui_profile_sig ~= profile_sig) then
        state.rule_ui_rule_sig = rule_sig;
        state.rule_ui_profile_sig = profile_sig;
        state.rule_ui_cache_dirty = true;
        state.rule_ui_scroll_y = 0;
        state.rule_ui_pending_wheel = 0;
    end
    if (state.rule_ui_cache_dirty ~= true and state.rule_ui_cache ~= nil) then
        return state.rule_ui_cache;
    end
    local zn = (zid ~= 0) and get_zone_name(zid) or nil;
    if (zn == nil or zn == '') then
        zn = 'Unknown Zone';
    end
    local rows = build_rule_rows();
    local item_count = #rows;
    local cache = {
        zone_id = zid,
        zone_title = format_rule_ui_zone_title(zn, zid, is_ignored_zone(), item_count),
        profiles_text = string.format('[%s] loaded.', profile_files_string()),
        rows = rows,
        item_count = item_count,
        show_scrollbar = (#rows > max_rows),
    };
    cache.base_w = estimate_rule_ui_base_width(cache);
    state.rule_ui_cache = cache;
    state.rule_ui_cache_dirty = false;
    return state.rule_ui_cache;
end
local function render_rule_list_ui()
    ensure_rule_ui_state();
    clear_rule_ui_interactive_rects();
    if (state.rule_ui_open == nil or state.rule_ui_open[1] ~= true) then
        state.rule_ui_dragging = false;
        return;
    end
    if (not is_player_logged_in()) then
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        return;
    end
    local zid_now = get_current_zone_id() or 0;
    if (zid_now == 0 or tonumber(state.current_profile_zone_id) ~= zid_now) then
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        return;
    end
    local scale_pct = tonumber(gSettings.RuleUI.scale) or 100;
    if (scale_pct < 50) then scale_pct = 50; end
    if (scale_pct > 400) then scale_pct = 400; end
    local scale = scale_pct / 100.0;
    local opacity_pct = tonumber(gSettings.RuleUI.opacity) or 100;
    if (opacity_pct < 30) then opacity_pct = 30; end
    if (opacity_pct > 100) then opacity_pct = 100; end
    local opacity = opacity_pct / 100.0;
    local max_rows = get_effective_rule_ui_max_rows();
    local cache_for_size = refresh_rule_ui_cache(max_rows);
    local base_w = math.max(tonumber(gSettings.RuleUI.w) or 420, tonumber(cache_for_size.base_w) or 420);
    local win_w = math.floor((base_w * scale) + 0.5);
    local base_line_h = get_rule_ui_base_line_height();
    local measured_line_h = tonumber(state.rule_ui_line_h) or 0;
    local line_h_guess = measured_line_h;
    if (line_h_guess <= 0) then
        line_h_guess = math.max(base_line_h, math.floor((base_line_h * math.max(scale, 1.0)) + 0.5));
    end
    state.rule_ui_scroll_step = math.max(12, math.floor((line_h_guess * 2.0) + 0.5));
    local visible_rows = math.max(1, math.min(max_rows, #(cache_for_size.rows or {})));
    local btn_h = math.max(16, math.floor((18 * scale) + 0.5));
    local row_gap = math.max(2, math.floor((2 * scale) + 0.5));
    local outer_pad = math.max(6, math.floor((6 * scale) + 0.5));
    local separator_h = math.max(6, math.floor((6 * scale) + 0.5));
    local header_h = math.max(line_h_guess, btn_h) + row_gap;
    local info_h = line_h_guess;
    local child_h = math.ceil((line_h_guess * visible_rows) + math.max(4, math.floor((4 * scale) + 0.5)));
    local approx_h = header_h + outer_pad;
    if (gSettings.RuleUI.minimized ~= true) then
        approx_h = header_h + info_h + separator_h + child_h + outer_pad;
    end
    apply_rule_ui_saved_pos_once(win_w, approx_h);
    local cur_x = tonumber(gSettings.RuleUI.x) or 100;
    local cur_y = tonumber(gSettings.RuleUI.y) or 100;
    set_next_rule_ui_pos(cur_x, cur_y);
    set_next_rule_ui_size(win_w, approx_h);
    local color_pushes = 0;
    if (imgui.PushStyleColor ~= nil) then
        imgui.PushStyleColor(ImGuiCol_WindowBg,              { 0.06, 0.06, 0.06, math.max(0.12, 0.94 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_TitleBg,               { 0.10, 0.10, 0.10, math.max(0.12, 0.82 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_TitleBgActive,         { 0.14, 0.14, 0.14, math.max(0.12, 0.94 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_ChildBg,               { 0.08, 0.08, 0.08, math.max(0.10, 0.88 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_Border,                { 0.78, 0.78, 0.78, math.max(0.10, 0.80 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_Text,                  { 1.00, 1.00, 1.00, math.max(0.10, opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_ScrollbarBg,           { 0.04, 0.04, 0.04, math.max(0.20, 0.94 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrab,         { 0.16, 0.16, 0.16, math.max(0.30, 0.98 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered,  { 0.26, 0.26, 0.26, math.max(0.35, 1.00 * opacity) }); color_pushes = color_pushes + 1;
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive,   { 0.40, 0.40, 0.40, math.max(0.40, 1.00 * opacity) }); color_pushes = color_pushes + 1;
    end
    local flags = 0;
    if (bit ~= nil) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove);
        flags = bit.bor(flags, ImGuiWindowFlags_NoResize);
        flags = bit.bor(flags, ImGuiWindowFlags_NoSavedSettings);
        flags = bit.bor(flags, ImGuiWindowFlags_NoTitleBar);
        if (ImGuiWindowFlags_NoScrollbar ~= nil) then
            flags = bit.bor(flags, ImGuiWindowFlags_NoScrollbar);
        end
        if (ImGuiWindowFlags_NoScrollWithMouse ~= nil) then
            flags = bit.bor(flags, ImGuiWindowFlags_NoScrollWithMouse);
        end
    end
    local opened = state.rule_ui_open;
    local toggled_minimize = false;
    local did_close = false;
    local did_begin = imgui.Begin('##zzl_rules', opened, flags);
    if (imgui.SetWindowFontScale ~= nil) then
        imgui.SetWindowFontScale(scale);
    end
    if (imgui.GetTextLineHeightWithSpacing ~= nil) then
        local ok_lh, lh = pcall(function () return imgui.GetTextLineHeightWithSpacing(); end);
        if (ok_lh and lh ~= nil and tonumber(lh) ~= nil and tonumber(lh) > 0) then
            state.rule_ui_line_h = tonumber(lh);
        end
    end
    local win_pos_x, win_pos_y = cur_x, cur_y;
    if (imgui.GetWindowPos ~= nil) then
        local ok_, x, y = pcall(function () return imgui.GetWindowPos(); end);
        if (ok_ and x ~= nil and y ~= nil) then
            win_pos_x = tonumber(x) or cur_x;
            win_pos_y = tonumber(y) or cur_y;
        end
    end
    local win_size_x, win_size_y = win_w, approx_h;
    if (imgui.GetWindowSize ~= nil) then
        local ok_, w, h = pcall(function () return imgui.GetWindowSize(); end);
        if (ok_ and w ~= nil and h ~= nil) then
            win_size_x = tonumber(w) or win_w;
            win_size_y = tonumber(h) or approx_h;
        end
    end
    state.rule_ui_rect = {
        x = win_pos_x,
        y = win_pos_y,
        w = win_size_x,
        h = win_size_y,
        title_h = header_h,
    };
    gSettings.RuleUI.x = math.floor((win_pos_x or cur_x) + 0.5);
    gSettings.RuleUI.y = math.floor((win_pos_y or cur_y) + 0.5);
    if (did_begin) then
        local cache = refresh_rule_ui_cache(max_rows);
        local zone_title = cache.zone_title;
        local profiles_text = cache.profiles_text or string.format('[%s.lua] loaded.', zone_default_profile_name());
        local rows = cache.rows;
        local show_scrollbar = cache.show_scrollbar;
        state.rule_ui_has_scrollbar = (show_scrollbar == true);
        if (show_scrollbar ~= true) then
            state.rule_ui_scroll_y = 0;
            state.rule_ui_pending_wheel = 0;
        end
        if (state.rule_ui_pending_action ~= nil) then
            if (state.rule_ui_pending_action == 'toggle_min') then
                gSettings.RuleUI.minimized = not (gSettings.RuleUI.minimized == true);
                toggled_minimize = true;
            elseif (state.rule_ui_pending_action == 'close') then
                did_close = true;
                opened[1] = false;
            end
            state.rule_ui_pending_action = nil;
        end
        local ignore_widget_result = (toggled_minimize or did_close);
        local button_pushes = 0;
        if (imgui.PushStyleColor ~= nil) then
            imgui.PushStyleColor(ImGuiCol_Button,        { 0.05, 0.05, 0.05, math.max(0.35, 0.96 * opacity) }); button_pushes = button_pushes + 1;
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.12, 0.12, 0.12, math.max(0.35, 0.98 * opacity) }); button_pushes = button_pushes + 1;
            imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.18, 0.18, 0.18, math.max(0.35, 1.00 * opacity) }); button_pushes = button_pushes + 1;
        end
        local btn_w = math.floor((28 * scale) + 0.5);
        local btn_gap = math.floor((4 * scale) + 0.5);
        local buttons_total = (btn_w * 2) + btn_gap;
        local btn_x = nil;
        if (imgui.GetWindowWidth ~= nil and imgui.SetCursorPosX ~= nil) then
            local ok_, ww = pcall(function () return imgui.GetWindowWidth(); end);
            if (ok_ and ww ~= nil) then
                btn_x = math.max(8, (tonumber(ww) or win_w) - buttons_total - 12);
            end
        end
        imgui.Text(zone_title);
        if (btn_x ~= nil and imgui.SetCursorPosX ~= nil) then
            imgui.SameLine();
            imgui.SetCursorPosX(btn_x);
        else
            imgui.SameLine();
        end
        local min_bx, min_by = 0, 0;
        if (imgui.GetCursorScreenPos ~= nil) then
            local ok_, x, y = pcall(function () return imgui.GetCursorScreenPos(); end);
            if (ok_) then
                min_bx = tonumber(x) or 0;
                min_by = tonumber(y) or 0;
            end
        end
        local min_clicked = imgui.SmallButton(gSettings.RuleUI.minimized and '[+]' or '[-]');
        if (not ignore_widget_result and min_clicked) then
            gSettings.RuleUI.minimized = not (gSettings.RuleUI.minimized == true);
            state.rule_ui_measured_h = nil;
            state.rule_ui_line_h = nil;
            toggled_minimize = true;
        end
        set_rule_ui_rect('min_button', min_bx, min_by, min_bx + btn_w, min_by + btn_h);
        imgui.SameLine();
        local close_bx, close_by = 0, 0;
        if (imgui.GetCursorScreenPos ~= nil) then
            local ok_, x, y = pcall(function () return imgui.GetCursorScreenPos(); end);
            if (ok_) then
                close_bx = tonumber(x) or 0;
                close_by = tonumber(y) or 0;
            end
        end
        local close_clicked = imgui.SmallButton('[x]');
        if (not ignore_widget_result and close_clicked) then
            did_close = true;
            opened[1] = false;
        end
        set_rule_ui_rect('close_button', close_bx, close_by, close_bx + btn_w, close_by + btn_h);
        if (button_pushes > 0 and imgui.PopStyleColor ~= nil) then
            imgui.PopStyleColor(button_pushes);
        end
        if (gSettings.RuleUI.minimized ~= true) then
            imgui.Text(profiles_text);
            imgui.Separator();
            local line_h = tonumber(state.rule_ui_line_h) or get_rule_ui_base_line_height();
            if (line_h == nil or line_h < base_line_h) then
                line_h = base_line_h;
            end
            local visible_rows = math.max(1, math.min(max_rows, #rows));
            child_h = math.ceil((line_h * visible_rows) + math.max(4, math.floor((4 * scale) + 0.5)));
            local child_flags = 0;
            if (show_scrollbar ~= true and bit ~= nil) then
                if (ImGuiWindowFlags_NoScrollbar ~= nil) then
                    child_flags = bit.bor(child_flags, ImGuiWindowFlags_NoScrollbar);
                end
                if (ImGuiWindowFlags_NoScrollWithMouse ~= nil) then
                    child_flags = bit.bor(child_flags, ImGuiWindowFlags_NoScrollWithMouse);
                end
            end
            local child_start_x, child_start_y = nil, nil;
            if (imgui.GetCursorScreenPos ~= nil) then
                local ok_, x, y = pcall(function () return imgui.GetCursorScreenPos(); end);
                if (ok_) then
                    child_start_x = tonumber(x);
                    child_start_y = tonumber(y);
                end
            end
            local begin_child_ok = false;
            local ok_child = pcall(function ()
                begin_child_ok = imgui.BeginChild('zzl_rules_child', { 0, child_h }, true, child_flags);
            end);
            if (not ok_child) then
                begin_child_ok = imgui.BeginChild('zzl_rules_child', { 0, child_h }, true);
            end
            if (#rows == 0) then
                imgui.Text('(empty)');
            else
                local child_content_w = nil;
                if (imgui.GetWindowWidth ~= nil) then
                    local ok_cw, cw = pcall(function () return imgui.GetWindowWidth(); end);
                    if (ok_cw and cw ~= nil) then
                        child_content_w = tonumber(cw);
                    end
                end
                if (child_content_w == nil or child_content_w <= 0) then
                    child_content_w = math.max(220, win_w - math.max(16, math.floor((18 * scale) + 0.5)));
                end
                local line_h_for_cols = tonumber(state.rule_ui_line_h) or get_rule_ui_base_line_height();
                local left_margin = math.max(6, math.floor((child_content_w * 0.02) + 0.5));
                local right_margin = left_margin;
                local scrollbar_pad = (show_scrollbar == true) and math.max(12, math.floor((16 * scale) + 0.5)) or 0;
                local usable_w = math.max(180, child_content_w - left_margin - right_margin - scrollbar_pad);
                local action_col_x = left_margin;
                local action_col_w = math.max(72, math.floor((usable_w * 0.18) + 0.5));
                local gap_w = math.max(10, math.floor((usable_w * 0.02) + 0.5));
                local id_sample_w = get_rule_ui_text_width('65535', line_h_for_cols);
                local id_col_w = math.max(48, math.min(math.floor((usable_w * 0.16) + 0.5), math.floor(id_sample_w + 8 + 0.5)));
                local id_col_x = math.max(action_col_x + action_col_w + gap_w + 80, child_content_w - right_margin - scrollbar_pad - id_col_w);
                local name_col_left = action_col_x + action_col_w + gap_w;
                local name_col_right = math.max(name_col_left + 60, id_col_x - gap_w);
                for _,r in ipairs(rows) do
                    local rule_text = tostring(r.rule or '');
                    local name_text = tostring(r.name or '');
                    local id_text = tostring(r.id or '');
                    local id_text_w = get_rule_ui_text_width(id_text, line_h_for_cols);
                    local id_text_x = math.max(name_col_left, id_col_x + math.max(0, math.floor((id_col_w - id_text_w) + 0.5)));
                    local name_text_w = get_rule_ui_text_width(name_text, line_h_for_cols);
                    local name_band_w = math.max(40, name_col_right - name_col_left);
                    local name_text_x = name_col_left;
                    if (name_text_w < name_band_w) then
                        name_text_x = name_col_left + math.max(0, math.floor(((name_band_w - name_text_w) * 0.5) + 0.5));
                    end
                    imgui.Text(rule_text);
                    imgui.SameLine();
                    if (imgui.SetCursorPosX ~= nil) then
                        imgui.SetCursorPosX(name_text_x);
                    end
                    imgui.Text(name_text);
                    imgui.SameLine();
                    if (imgui.SetCursorPosX ~= nil) then
                        imgui.SetCursorPosX(id_text_x);
                    end
                    imgui.Text(id_text);
                end
            end
            local pending_wheel = 0;
            if (show_scrollbar == true and imgui.GetIO ~= nil) then
                local mx = tonumber(state.mouse_x) or 0;
                local my = tonumber(state.mouse_y) or 0;
                if (rule_ui_hits_window(mx, my) and not rule_ui_hits_button(mx, my)) then
                    local ok_io, io = pcall(function () return imgui.GetIO(); end);
                    if (ok_io and io ~= nil and io.MouseWheel ~= nil) then
                        local wheel = tonumber(io.MouseWheel) or 0;
                        if (wheel > 0) then pending_wheel = 1;
                        elseif (wheel < 0) then pending_wheel = -1; end
                    end
                end
            end
            if (imgui.GetScrollY ~= nil and imgui.GetScrollMaxY ~= nil and imgui.SetScrollY ~= nil) then
                pcall(function ()
                    local cur = tonumber(imgui.GetScrollY()) or 0;
                    local maxy = tonumber(imgui.GetScrollMaxY()) or 0;
                    local nexty = cur;
                    if (pending_wheel ~= 0) then
                        nexty = cur - (pending_wheel * (tonumber(state.rule_ui_scroll_step) or 48));
                    end
                    if (nexty < 0) then nexty = 0; end
                    if (nexty > maxy) then nexty = maxy; end
                    if (math.abs(nexty - cur) > 0.5) then
                        imgui.SetScrollY(nexty);
                    end
                    state.rule_ui_scroll_y = nexty;
                    state.rule_ui_pending_wheel = 0;
                end);
            end
            imgui.EndChild();
            local child_x1, child_y1, child_x2, child_y2 = nil, nil, nil, nil;
            if (imgui.GetItemRectMin ~= nil and imgui.GetItemRectMax ~= nil) then
                local ok_min, minx, miny = pcall(function() return imgui.GetItemRectMin(); end);
                local ok_max, maxx, maxy = pcall(function() return imgui.GetItemRectMax(); end);
                if (ok_min and ok_max) then
                    child_x1 = tonumber(minx);
                    child_y1 = tonumber(miny);
                    child_x2 = tonumber(maxx);
                    child_y2 = tonumber(maxy);
                end
            end
            if (child_x1 ~= nil and child_y1 ~= nil and child_x2 ~= nil and child_y2 ~= nil) then
                set_rule_ui_rect('child_area', child_x1, child_y1, child_x2, child_y2);
            elseif (child_start_x ~= nil and child_start_y ~= nil) then
                set_rule_ui_rect('child_area', child_start_x, child_start_y, child_start_x + math.max(0, win_w - 16), child_start_y + child_h);
            else
                set_rule_ui_rect('child_area', -1, -1, -2, -2);
            end
            if (child_x1 ~= nil and child_y1 ~= nil and child_x2 ~= nil and child_y2 ~= nil and show_scrollbar == true) then
                local sb_w = math.max(12, math.floor((14 * scale) + 0.5));
                set_rule_ui_rect('scrollbar', child_x2 - sb_w, child_y1, child_x2, child_y2);
            else
                set_rule_ui_rect('scrollbar', -1, -1, -2, -2);
            end
            state.rule_ui_measured_h = nil;
        else
            state.rule_ui_has_scrollbar = false;
            state.rule_ui_scroll_y = 0;
            state.rule_ui_pending_wheel = 0;
            state.rule_ui_measured_h = math.floor(header_h + outer_pad + 0.5);
            set_rule_ui_rect('child_area', -1, -1, -2, -2);
            set_rule_ui_rect('scrollbar', -1, -1, -2, -2);
        end
    end
    imgui.End();
    if (color_pushes > 0 and imgui.PopStyleColor ~= nil) then
        imgui.PopStyleColor(color_pushes);
    end
    if (toggled_minimize) then
        settings.save();
        return;
    end
    if (did_close or opened[1] == false) then
        state.rule_ui_dragging = false;
        set_rule_ui_visible(false);
        return;
    end
    gSettings.RuleUI.visible = true;
end
local function wc_to_luapattern(wc)
    local function esc(s)
        return s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1");
    end
    local p = esc(wc);
    p = p:gsub("%%%*", ".*");
    p = p:gsub("%%%?", ".");
    return '^' .. p .. '$';
end
local function any_wc_match(name, wc)
    if (wc == nil) then return false; end
    wc = tostring(wc):lower();
    local parts = {};
    for part in wc:gmatch('[^|]+') do
        table.insert(parts, part);
    end
    for _,part in ipairs(parts) do
        local pat = wc_to_luapattern(part);
        if (name:match(pat) ~= nil) then return true; end
    end
    return false;
end
local item_index = nil; -- map lower_name -> id
local function build_item_index()
    if (item_index ~= nil) then return; end
    item_index = {};
    local rm = AshitaCore:GetResourceManager();
    if (rm == nil) then
        warn('ResourceManager unavailable; wildcard matching disabled.');
        return;
    end
    local max_id = 25000;
    local nil_run = 0;
    for id = 1, max_id do
        local it = rm:GetItemById(id);
        if (it ~= nil) then
            local function add_name(s)
                if (s == nil) then return; end
                s = tostring(s):gsub('[%z\1-\31\127]', ''):trim():lower();
                if (s ~= '' and item_index[s] == nil) then
                    item_index[s] = id;
                end
            end
            if (it.Name ~= nil) then
                for _,idx in ipairs({ 1, 0, 2, 3 }) do
                    add_name(it.Name[idx]);
                end
            end
            if (it.LogNameSingular ~= nil) then
                for _,idx in ipairs({ 1, 0, 2, 3 }) do
                    add_name(it.LogNameSingular[idx]);
                end
            end
            if (it.LogNamePlural ~= nil) then
                for _,idx in ipairs({ 1, 0, 2, 3 }) do
                    add_name(it.LogNamePlural[idx]);
                end
            end
            nil_run = 0;
else
            nil_run = nil_run + 1;
            if (nil_run > 750) then
                break;
            end
        end
    end
end
local keyword_ids = {
    seals      = {1126, 1127, 2955, 2956, 2957},
    currency   = {1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457},
    geodes     = {3297, 3298, 3299, 3300, 3301, 3302, 3303, 3304},
    avatarites = {3520, 3521, 3522, 3523, 3524, 3525, 3526, 3527},
    crystals   = {4096, 4097, 4098, 4099, 4100, 4101, 4102, 4103},
    detritus   = {9875, 9876},
    heroism    = {9877, 9878},
    moldy      = {9773, 9830, 9831, 9832, 9833, 9834, 9835, 9836, 9837, 9838, 9839, 9840, 9841, 9843, 9868, 9869, 9870, 9871, 9872, 9873, 9874},
    dynad      = {9538, 9539, 9540, 9541, 9542, 9543, 9844, 9845},
    papers     = {9544, 9545, 9546, 9547, 9548, 9549, 9550, 9551, 9552, 9553, 9554, 9555, 9556, 9557, 9558, 9559, 9560, 9561, 9562, 9563, 9564, 9565, 9566, 9567, 9568, 9569, 9570, 9571, 9572, 9573, 9574, 9575, 9576, 9577, 9578, 9579, 9580, 9581, 9582, 9583, 9584, 9585, 9586, 9587, 9588, 9589, 9590, 9591, 9592, 9593, 9594, 9595, 9596, 9597, 9598, 9599, 9600, 9601, 9602, 9603, 9604, 9605, 9606, 9607, 9608, 9609, 9610, 9611, 9612, 9613, 9614, 9615, 9616, 9617, 9618, 9619, 9620, 9621, 9622, 9623, 9624, 9625, 9626, 9627, 9628, 9629, 9630, 9631, 9632, 9633, 9634, 9635, 9636, 9637, 9638, 9639, 9640, 9641, 9642, 9643, 9644, 9645, 9646, 9647, 9648, 9649, 9650, 9651, 9652, 9653, 9654, 9655, 9656, 9657, 9658, 9659, 9660, 9661, 9662, 9663, 9664, 9665, 9666, 9667, 9668, 9669, 9670, 9671, 9672, 9673, 9674, 9675, 9676, 9677, 9678, 9679, 9680, 9681, 9682, 9683, 9684, 9685, 9686, 9687, 9688, 9689, 9690, 9691, 9692, 9693, 9694, 9695, 9696, 9697, 9698, 9699, 9700, 9701, 9702, 9703, 9704, 9705, 9706, 9707, 9708, 9709, 9710, 9711, 9712, 9713, 9714, 9715, 9716, 9717, 9718, 9719, 9720, 9721, 9722, 9723, 9724, 9725, 9726, 9727, 9728, 9729, 9730, 9731, 9732, 9733, 9734, 9735, 9736, 9737, 9738, 9739, 9740, 9741, 9742, 9743, 9744, 9745, 9746, 9747, 9748, 9749, 9750, 9751, 9752, 9753, 9754, 9755, 9756, 9757, 9758, 9759, 9760, 9761, 9762, 9763},
};
state = {
    pool_ids = {}, pool_status = {}, actions = {}, inv_dirty = false, drop_pending = false, last_sort = 0,
    pool_empty_since = os.clock(), auto_zone_id = 0, auto_attempted = false,
    shift_down = false, last_ui_save = 0, rule_ui_open = nil, rule_ui_apply_saved_pos = true,
    rule_ui_cache_dirty = true, rule_ui_cache = nil, rule_ui_last_zone_id = -1, rule_ui_pending_action = nil,
    rule_ui_button_capture = nil, rule_ui_pending_wheel = 0, rule_ui_scroll_step = 48, rule_ui_has_scrollbar = false,
    rule_ui_scroll_y = 0, rule_ui_measured_h = nil, rule_ui_line_h = nil, rule_ui_rule_sig = nil,
    mouse_x = 0, mouse_y = 0,
    current_profile_zone_id = -1,
    runtime_profile_dirty = false, runtime_profile_dirty_reason = nil,
    lot_skip_notified = {},
    lot_rejected_current_pool = {},
    recent_lot_attempts = {},
    deferred_warns = {},
};
for i = 0, 9 do state.pool_ids[i] = 0; state.pool_status[i] = 0; end
local function pool_unique_ids()
    local seen = {};
    local out = {};
    for i = 0, 9 do
        local id = tonumber(state.pool_ids[i]) or 0;
        if (id ~= 0 and not seen[id]) then
            seen[id] = true;
            table.insert(out, id);
        end
    end
    return out;
end
local function pool_is_empty()
    for i = 0, 9 do
        local id = tonumber(state.pool_ids[i]) or 0;
        if (id ~= 0) then return false; end
    end
    return true;
end
local function update_pool_empty_state()
    local now = os.clock();
    if (pool_is_empty()) then
        if (state.pool_empty_since == nil) then
            state.pool_empty_since = now;
        end
        if (#state.actions > 0) then
            state.actions = {};
        end
    else
        state.pool_empty_since = nil;
    end
end
local function is_pool_quiet()
    if (state.pool_empty_since == nil) then return false; end
    return (os.clock() - state.pool_empty_since) > 1.0;
end
local function can_network()
    if (not is_active()) then return false; end
    if (is_pool_quiet()) then return false; end
    return true;
end
local function random_delay()
    local maxd = tonumber(gSettings.Delay) or 0
    if (maxd <= 0) then
        maxd = 2.0
    end
    if (maxd < 0.5) then
        maxd = 0.5
    end
    return 0.5 + (math.random() * (maxd - 0.5))
end
local function enqueue_action(kind, fn, args, delay)
    if (not can_network()) then
        verbose_msg('Paused/disabled; ignoring queued action: ' .. tostring(kind));
        return;
    end
    delay = delay or random_delay();
    local at = os.clock() + delay;
    table.insert(state.actions, {
        at = at,
        kind = kind,
        fn = fn,
        args = args or {},
    });
end
local function process_actions()
    if (#state.actions == 0) then return; end
    local now = os.clock();
    table.sort(state.actions, function(a, b) return a.at < b.at; end);
    local i = 1;
    while (i <= #state.actions) do
        local a = state.actions[i];
        if (a.at > now) then break; end
        table.remove(state.actions, i);
        local ok_, err_ = pcall(function()
            a.fn(unpack(a.args));
        end);
        if (not ok_) then
            warn('Action failed: ' .. tostring(err_));
        end
    end
end
local function can_inject()
    local pm = AshitaCore and AshitaCore:GetPacketManager() or nil;
    if (pm == nil) then
        err('PacketManager is not available. (AshitaCore:GetPacketManager returned nil.)');
        return false;
    end
    if (type(struct) ~= 'table' or type(struct.pack) ~= 'function') then
        err('struct.pack is not available.');
        return false;
    end
    return true;
end
local function remember_lot_attempt(slot, itemId)
    slot = tonumber(slot) or 0;
    itemId = tonumber(itemId) or 0;
    if (slot < 0 or slot > 9 or itemId == 0) then return; end
    table.insert(state.recent_lot_attempts, {
        at = os.clock(),
        slot = slot,
        itemId = itemId,
    });
    while (#state.recent_lot_attempts > 20) do
        table.remove(state.recent_lot_attempts, 1);
    end
end
local function inject_lot(slot)
    if (not can_inject()) then return; end
    local pm = AshitaCore:GetPacketManager();
    slot = tonumber(slot) or 0;
    local itemId = tonumber(state.pool_ids[slot]) or 0;
    local p = struct.pack('BBHBxxx', 0x41, 0x08, 0, slot):totable();
    pm:AddOutgoingPacket(0x41, p);
    remember_lot_attempt(slot, itemId);
    state.pool_status[slot] = 1;
end
local function inject_pass(slot)
    if (not can_inject()) then return; end
    local pm = AshitaCore:GetPacketManager();
    slot = tonumber(slot) or 0;
    local p = struct.pack('BBHBxxx', 0x42, 0x08, 0, slot):totable();
    pm:AddOutgoingPacket(0x42, p);
    state.pool_status[slot] = 2;
end
local function inject_sort(bag)
    if (not can_inject()) then return; end
    local pm = AshitaCore:GetPacketManager();
    bag = tonumber(bag) or 0;
    local p = struct.pack('BBHBBH', 0x3A, 0x08, 0, bag, 0, 0):totable();
    pm:AddOutgoingPacket(0x3A, p);
    state.last_sort = os.clock();
end
local function inject_drop(bag, index, count)
    if (not can_inject()) then return; end
    local pm = AshitaCore:GetPacketManager();
    bag   = tonumber(bag) or 0;
    index = tonumber(index) or 0;
    count = tonumber(count) or 0;
    if (index <= 0 or count <= 0) then return; end
    local p = struct.pack('BBHIBBH', 0x28, 0x0C, 0, count, bag, index, 0):totable();
    pm:AddOutgoingPacket(0x28, p);
end
local function get_inventory_free_slots()
    local inv = get_inventory_manager();
    if (inv == nil) then return 0; end
    local used = inventory_get_container_count(inv, 0);
    local max = inventory_get_container_max(inv, 0);
    if (used ~= nil and max ~= nil) then
        return math.max(0, (tonumber(max) or 0) - (tonumber(used) or 0));
    end
    max = inventory_get_container_max(inv, 0);
    if (max == nil) then return 0; end
    local count = 0;
    for i = 1, max do
        local it = inventory_get_item(inv, 0, i);
        if (it ~= nil and it.Id ~= nil and it.Id ~= 0) then
            count = count + 1;
        end
    end
    return max - count;
end
local ITEM_FLAG_EX   = 0x4000;
local ITEM_FLAG_RARE = 0x8000;
local function get_item_resource_flags(itemId)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0) then return 0; end
    local rm = (AshitaCore ~= nil and AshitaCore.GetResourceManager ~= nil) and AshitaCore:GetResourceManager() or nil;
    if (rm == nil or rm.GetItemById == nil) then return 0; end
    local ok_, item = pcall(function () return rm:GetItemById(itemId); end);
    if (not ok_ or item == nil or item.Flags == nil) then return 0; end
    return tonumber(item.Flags) or 0;
end
local function is_item_rare_or_ex(itemId)
    local flags = get_item_resource_flags(itemId);
    if (bit == nil) then return false, false; end
    local is_rare = bit.band(flags, ITEM_FLAG_RARE) == ITEM_FLAG_RARE;
    local is_ex = bit.band(flags, ITEM_FLAG_EX) == ITEM_FLAG_EX;
    return is_rare, is_ex;
end
local function player_has_item_in_any_bag(itemId)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0) then return false; end
    local inv = get_inventory_manager();
    if (inv == nil) then return false; end
    for bag = 0, 16 do
        local max = tonumber(inventory_get_container_max(inv, bag)) or 0;
        if (max > 0) then
            for slot = 1, max do
                local it = inventory_get_item(inv, bag, slot);
                local existing_id = tonumber(it ~= nil and it.Id or 0) or 0;
                if (existing_id == itemId) then
                    return true, bag, slot;
                end
            end
        end
    end
    return false;
end
local function defer_warn(msg)
    msg = tostring(msg or ''):trim();
    if (msg == '') then return; end
    table.insert(state.deferred_warns, msg);
end
local function flush_deferred_warns()
    if (state.deferred_warns == nil or #state.deferred_warns == 0) then return; end
    local queued = state.deferred_warns;
    state.deferred_warns = {};
    for _, msg_ in ipairs(queued) do
        warn(msg_);
    end
end
local function pool_contains_item(itemId)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0) then return false; end
    for i = 0, 9 do
        if ((tonumber(state.pool_ids[i]) or 0) == itemId) then
            return true;
        end
    end
    return false;
end
local function pool_contains_item_except_slot(itemId, slot)
    itemId = tonumber(itemId) or 0;
    slot = tonumber(slot) or -1;
    if (itemId == 0) then return false; end
    for i = 0, 9 do
        if (i ~= slot and (tonumber(state.pool_ids[i]) or 0) == itemId) then
            return true;
        end
    end
    return false;
end
local function clear_lot_rejection_if_item_left_pool(itemId)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0) then return; end
    if (pool_contains_item(itemId)) then return; end
    state.lot_skip_notified[itemId] = nil;
    state.lot_rejected_current_pool[itemId] = nil;
end
local function prune_recent_lot_attempts(max_age)
    max_age = tonumber(max_age) or 6.0;
    local now = os.clock();
    for i = #state.recent_lot_attempts, 1, -1 do
        local entry = state.recent_lot_attempts[i];
        local age = now - (tonumber(entry ~= nil and entry.at or 0) or 0);
        local itemId = tonumber(entry ~= nil and entry.itemId or 0) or 0;
        if (age > max_age or itemId == 0 or not pool_contains_item(itemId)) then
            table.remove(state.recent_lot_attempts, i);
        end
    end
end
local function consume_recent_lot_attempt(max_age)
    prune_recent_lot_attempts(max_age);
    for i = #state.recent_lot_attempts, 1, -1 do
        local entry = state.recent_lot_attempts[i];
        local itemId = tonumber(entry ~= nil and entry.itemId or 0) or 0;
        local slot = tonumber(entry ~= nil and entry.slot or 0) or 0;
        if (itemId ~= 0 and pool_contains_item(itemId)) then
            table.remove(state.recent_lot_attempts, i);
            return itemId, slot;
        end
    end
    return 0, 0;
end
local function classify_lot_rejection_message(message)
    local s = tostring(message or ''):lower();
    s = s:gsub('%s+', ' '):trim();
    if (s == '') then return nil; end
    if (s:find('only hold one of that item', 1, true) ~= nil) then
        return 'rare_duplicate_server';
    end
    if (s:find('only hold one item of that type', 1, true) ~= nil) then
        return 'rare_duplicate_server';
    end
    if ((s:find('could not obtain', 1, true) ~= nil or s:find('cannot obtain', 1, true) ~= nil) and s:find('one item of that type', 1, true) ~= nil) then
        return 'rare_duplicate_server';
    end
    if (s:find('inventory is full', 1, true) ~= nil) then
        return 'inventory_full_server';
    end
    if (s:find('no inventory space', 1, true) ~= nil or s:find('no inventory spaces', 1, true) ~= nil) then
        return 'inventory_full_server';
    end
    if (s:find('come back after sorting your inventory', 1, true) ~= nil) then
        return 'inventory_full_server';
    end
    return nil;
end
local function build_lot_rejection_notice(itemId, reason)
    local item_name = get_item_name(itemId);
    if (reason == 'rare_duplicate_server') then
        return string.format('LOT failed for %s because the game says you can only hold one of that item. Handle it manually and remove it from the current LOT list if you never want zzloot to try it again for this drop.', item_name);
    end
    if (reason == 'inventory_full_server') then
        return string.format('LOT failed for %s because your inventory had no free slot when the lot resolved. Free 1 slot before the next drop.', item_name);
    end
    return string.format('LOT failed for %s. Handle it manually if needed.', item_name);
end
local function mark_lot_item_rejected_for_current_pool(itemId, reason)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0 or reason == nil) then return; end
    state.lot_rejected_current_pool[itemId] = reason;
    for i = 0, 9 do
        if ((tonumber(state.pool_ids[i]) or 0) == itemId and (tonumber(state.pool_status[i]) or 0) ~= 2) then
            state.pool_status[i] = 3;
        end
    end
    if (state.lot_skip_notified[itemId] ~= true) then
        state.lot_skip_notified[itemId] = true;
        defer_warn(build_lot_rejection_notice(itemId, reason));
    end
end
local function notify_lot_skip_once(itemId, text)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0 or text == nil or tostring(text):trim() == '') then return; end
    if (state.lot_skip_notified[itemId] == true) then return; end
    state.lot_skip_notified[itemId] = true;
    warn(text);
end
local function validate_lot_item(itemId)
    itemId = tonumber(itemId) or 0;
    if (itemId == 0) then
        return false, 'invalid_item';
    end
    local rejected_reason = state.lot_rejected_current_pool[itemId];
    if (rejected_reason ~= nil) then
        return false, rejected_reason;
    end
    if (get_inventory_free_slots() <= 0) then
        return false, 'inventory_full';
    end
    local is_rare = false;
    is_rare = select(1, is_item_rare_or_ex(itemId));
    if (is_rare) then
        local has_item = player_has_item_in_any_bag(itemId);
        if (has_item == true) then
            return false, 'rare_duplicate';
        end
    end
    return true, nil;
end
local function inventory_scan_drop_one()
    if (not gSettings.AutoDrop) then return false; end
    if (state.drop_pending) then return false; end
    local inv = get_inventory_manager();
    if (inv == nil) then return false; end
    local max = inventory_get_container_max(inv, 0);
    if (max == nil) then return false; end
    for i = 1, max do
        local it = inventory_get_item(inv, 0, i);
        if (it ~= nil and it.Id ~= nil and it.Id ~= 0) then
            local id = tonumber(it.Id) or 0;
            local count = tonumber(it.Count) or 0;
            local flags = tonumber(it.Flags) or 0;
            if (id ~= 0 and count > 0 and flags == 0 and compiled.Drop[id]) then
                verbose_msg(string.format('Dropping: %dx %s', count, get_item_name(id)));
                state.drop_pending = true;
                enqueue_action('drop', function(bag, idx, cnt)
                    inject_drop(bag, idx, cnt);
                    state.drop_pending = false;
                    state.inv_dirty = true;
                end, {0, i, count}, random_delay());
                return true;
            end
        end
    end
    return false;
end
local function request_sort()
    if (not gSettings.AutoStack) then return; end
    local now = os.clock();
    if (now - state.last_sort < 2.0) then
        return;
    end
    enqueue_action('sort', function()
        inject_sort(0);
    end, {}, random_delay());
end
local function handle_inventory_dirty()
    if (not can_network()) then return; end
    if (not state.inv_dirty) then return; end
    state.inv_dirty = false;
    local dropped = inventory_scan_drop_one();
    if (not dropped) then
        request_sort();
    end
end
local function decide_pool_slot(slot, itemId)
    if (not is_active()) then return; end
    slot = tonumber(slot) or 0;
    itemId = tonumber(itemId) or 0;
    if (slot < 0 or slot > 9 or itemId == 0) then return; end
    if (state.pool_status[slot] ~= 0) then return; end
    if (compiled.Drop[itemId] or compiled.Pass[itemId]) then
        verbose_msg(string.format('Passing: %s', get_item_name(itemId)));
        enqueue_action('pass', function(s) inject_pass(s); end, {slot}, random_delay());
        return;
    end
    if (compiled.Lot[itemId]) then
        local can_lot, reason = validate_lot_item(itemId);
        if (can_lot == true) then
            verbose_msg(string.format('Lotting: %s', get_item_name(itemId)));
            enqueue_action('lot', function(s) inject_lot(s); end, {slot}, random_delay());
            return;
        end
        state.pool_status[slot] = 3;
        local item_name = get_item_name(itemId);
        if (reason == 'inventory_full') then
            notify_lot_skip_once(itemId, string.format('Skipping LOT for %s because your inventory is full. Free 1 slot and it can lot next drop.', item_name));
        elseif (reason == 'rare_duplicate') then
            notify_lot_skip_once(itemId, string.format('Skipping LOT for %s because you already own a Rare copy. Remove it from the current LOT list if you never want to lot it.', item_name));
        elseif (reason == 'inventory_full_server') then
            notify_lot_skip_once(itemId, build_lot_rejection_notice(itemId, reason));
        elseif (reason == 'rare_duplicate_server') then
            notify_lot_skip_once(itemId, build_lot_rejection_notice(itemId, reason));
        end
        return;
    end
end
local function rescan_current_pool_rules(ids)
    local targets = {};
    for _,v in ipairs(ids or {}) do
        local id = tonumber(v) or 0;
        if (id ~= 0) then targets[id] = true; end
    end
    if (next(targets) == nil) then return false; end
    for i = #state.actions, 1, -1 do
        local a = state.actions[i];
        if (a ~= nil and (a.kind == 'lot' or a.kind == 'pass')) then
            local slot = tonumber(a.args and a.args[1]) or -1;
            local id = tonumber(state.pool_ids[slot]) or 0;
            if (targets[id] == true) then
                table.remove(state.actions, i);
            end
        end
    end
    local did = false;
    for slot = 0, 9 do
        local id = tonumber(state.pool_ids[slot]) or 0;
        local status = tonumber(state.pool_status[slot]) or 0;
        if (id ~= 0 and targets[id] == true and status ~= 1 and status ~= 2) then
            state.pool_status[slot] = 0;
            decide_pool_slot(slot, id);
            did = true;
        end
    end
    return did;
end
local function print_help(is_err)
    if (is_err) then
        err('Invalid command syntax. Try /zzl help');
    end
    msg('Commands:');
    msg('/zzl help');
    msg('/zzl auto [on|off]             (toggles auto-loading zone-matched profiles on first loot)');
    msg('/zzl zone                     (prints current ZoneId and ignore status)');
    msg('/zzl zone +i | /zzl zone -i   (add/remove current ZoneId to ignore list)');
    msg('/zzl zone list                (prints ignore list)');
    msg('/zzl load <Name> [<Name2>...] (appends unique rules and appends names to the current zone tooltip)');
    msg('/zzl unload <Name> [<Name2>...] (removes loaded profile(s) from the current zone set)');
    msg('/zzl save [<Name>]           (no name saves the current zone### profile; named saves do not need .lua)');
    msg('/zzl list                     (toggles on-screen rule list UI)');
        msg('/zzl list show|hide|toggle');
    msg('/zzl list show 3-99            (persistent visible row count; saved in player settings)');
    msg('/zzl list sort [alpha|recent]  (session-only sort mode; alpha = LOT/PASS/DROP then name)');
    msg('/zzl (scale|s) 50-400         (list UI scale; hold SHIFT for ~2s while not dragging to recover offscreen header/buttons to x=0,y=0)');
    msg('List UI buttons: [-]/[+] minimize or restore, [x] close. SHIFT+drag anywhere on the addon except the buttons to move it.');
    msg('/zzl (opacity|alpha|o) 30-100 (list UI opacity)');
    msg('/zzl reset                    (resets addon settings to defaults while preserving saved lists/profiles/ignore zones)');
    msg('/zzl (l|p|d) (+|-) <name|id...> (add/remove; rule and +/- may be swapped)');
    msg('/zzl - <name|id...>           (removes item from lot/pass/drop)');
    msg('Multi-word names require <...> or "...".');
    msg('/zzl (lot|pass|drop) (list|clear)');
    msg('/zzl lotall | passall | done | clearall');
    msg('/zzl clear                    (same as clearall; resets loaded profiles to the current zone default)');
    msg('/zzl delay <seconds>          (per-action delay is random in [0.5, Delay] when Delay>0 else [0.5, 2.0])');
    msg('/zzl (autodrop|autostack|verbose) [on|off]');
    msg('/zzl (on|off)                 (master enable toggle)');
    msg('Profiles are stored next to settings.lua under: config\\addons\\Zzloot\\<Name>_<ServerId>\\');
    msg('Zone bootstrap: on addon load or zone change, zzloot loads the last profile set saved for that ZoneId. If none exists, it creates zone###.lua for that zone.');
    msg('Workflow: load appends new profile rules into the current zone set, save writes a new named file without replacing older files, and unload removes named files from the current zone set.');
    msg('Special <name> keywords: pool, seals, currency, geodes, avatarites, crystals, detritus, heroism, moldy, dynad, papers');
end
local function resolve_ids(term)
    term = normalize_item_term(term);
    if (term == '') then return {}; end
    local lower = term:lower();
    if (lower == 'pool') then
        return pool_unique_ids();
    end
    local kw = keyword_ids[lower];
    if (kw ~= nil) then
        return kw;
    end
    if (lower:match('^%d+$') ~= nil) then
        return { tonumber(lower) };
    end
    local rm = AshitaCore:GetResourceManager();
    if (rm ~= nil) then
        local it = try_get_item_by_name(rm, term);
        if (it ~= nil) then
            return { tonumber(it.ItemId) };
        end
    end
    build_item_index();
    if (item_index == nil) then
        return {};
    end
    local wants_wc = (lower:find('%*') ~= nil) or (lower:find('%?') ~= nil) or (lower:find('|') ~= nil);
    if (not wants_wc) then
        local id = item_index[lower];
        if (id ~= nil) then
            return { id };
        end
        return {};
    end
    local ids = {};
    for name, id in pairs(item_index) do
        if (any_wc_match(name, lower)) then
            table.insert(ids, id);
        end
    end
    table.sort(ids);
    return ids;
end
local function list_name_from_mode(mode)
    mode = tostring(mode or ''):lower();
    if (mode == 'l') then return 'lot'; end
    if (mode == 'p') then return 'pass'; end
    if (mode == 'd') then return 'drop'; end
    return mode;
end
local function action_name_from_mode(mode)
    mode = tostring(mode or ''):lower();
    if (mode == 'a' or mode == '+') then return 'add'; end
    if (mode == 'r' or mode == '-') then return 'remove'; end
    return mode;
end
local function get_list_ref(which)
    which = tostring(which or ''):lower();
    if (which == 'lot') then return gSettings.Lot, compiled.Lot; end
    if (which == 'pass') then return gSettings.Pass, compiled.Pass; end
    if (which == 'drop') then return gSettings.Drop, compiled.Drop; end
    return nil, nil;
end
local function set_bool_setting(key, val)
    if (val == nil) then
        gSettings[key] = not gSettings[key];
    else
        gSettings[key] = val;
    end
    settings.save();
    rebuild_compiled();
    local out = string.format('%s: %s', key, tostring(gSettings[key]));
    if (key == 'Verbose') then
        echo(out);
    else
        ok(out);
    end
    if (key == 'AutoDrop' and gSettings[key] == true) then
        request_autodrop_rescan();
    end
end
local function extract_angle_terms(command)
    local out = {};
    command = tostring(command or '');
    for inner in command:gmatch('<([^<>]+)>') do
        inner = tostring(inner or ''):trim();
        if (inner ~= '') then
            table.insert(out, inner);
        end
    end
    return out;
end
local function parse_profile_term_tokens(args, start_idx)
    if (start_idx == nil or start_idx > #args) then
        return nil, 'missing';
    end
    local first = tostring(args[start_idx] or '');
    local function join_until(close_ch, errcode)
        local parts = { first };
        local i = start_idx + 1;
        while (i <= #args) do
            local tok = tostring(args[i] or '');
            table.insert(parts, tok);
            if (tok:find(close_ch, 1, true) ~= nil) then
                return table.concat(parts, ' '), i + 1;
            end
            i = i + 1;
        end
        return nil, errcode;
    end
    local lead = first:sub(1, 1);
    if (lead == '<') then
        if (first:find('>', 1, true) ~= nil) then
            return first, start_idx + 1;
        end
        return join_until('>', 'angle_unterminated');
    end
    if (lead == '[') then
        if (first:find(']', 1, true) ~= nil) then
            return first, start_idx + 1;
        end
        return join_until(']', 'bracket_unterminated');
    end
    if (lead == '"') then
        if (#first >= 2 and first:sub(-1) == '"') then
            return first, start_idx + 1;
        end
        return join_until('"', 'quote_unterminated');
    end
    return first, start_idx + 1;
end
local function collect_profile_terms(args, start_idx)
    local out = {};
    local i = start_idx or 1;
    while (i <= #args) do
        local term, next_i = parse_profile_term_tokens(args, i);
        if (term == nil) then
            return nil, next_i, i;
        end
        term = normalize_profile_term(term);
        if (term ~= '') then
            table.insert(out, term);
        end
        i = next_i;
    end
    return out, nil, nil;
end
local function parse_term_tokens(args, start_idx)
    if (start_idx == nil or start_idx > #args) then
        return nil, 'missing';
    end
    local first = tostring(args[start_idx] or '');
    local function join_until(predicate, errcode)
        local parts = { first };
        local i = start_idx + 1;
        while (i <= #args) do
            local tok = tostring(args[i] or '');
            table.insert(parts, tok);
            if (predicate(tok)) then
                return table.concat(parts, ' '), i + 1;
            end
            i = i + 1;
        end
        return nil, errcode;
    end
    if (first:sub(1, 1) == '<') then
        if (first:find('>', 1, true) ~= nil) then
            return first, start_idx + 1;
        end
        return join_until(function(tok) return tok:find('>', 1, true) ~= nil; end, 'angle_unterminated');
    end
    if (first:sub(1, 1) == '"') then
        if (#first >= 2 and first:sub(-1) == '"' and first:sub(-2, -2) ~= '\\') then
            return first, start_idx + 1;
        end
        return join_until(function(tok)
            return (#tok >= 1 and tok:sub(-1) == '"' and tok:sub(-2, -2) ~= '\\');
        end, 'quote_unterminated');
    end
    if (start_idx < #args) then
        return nil, 'needs_wrapping';
    end
    return first, start_idx + 1;
end
local function get_player_name_and_id()
    local name, sid = nil, nil;
    local p = get_party_manager();
    if (p ~= nil) then
        name = p:GetMemberName(0);
        sid  = p:GetMemberServerId(0);
    end
    if (name == nil or name == '' or sid == nil or tonumber(sid) == nil) then
        return nil, nil;
    end
    return tostring(name), tonumber(sid);
end
local function get_profiles_dir()
    local install = (AshitaCore and AshitaCore.GetInstallPath) and AshitaCore:GetInstallPath() or nil;
    if (install == nil or install == '') then
        return nil;
    end
    local name, sid = get_player_name_and_id();
    if (name == nil or sid == nil) then
        return nil;
    end
    return string.format('%sconfig\\addons\\%s\\%s_%d\\', install, addon.name, name, sid);
end
local function sanitize_profile_name(raw)
    local name = validate_profile_name(raw);
    return name;
end
local function get_profile_path(profile_name)
    local dir = get_profiles_dir();
    if (dir == nil) then return nil; end
    return dir .. profile_name .. '.lua';
end
local function write_profile_file(path, profile_name, zone_id, lot_list, pass_list, drop_list)
    local f, ferr = io.open(path, 'w+');
    if (f == nil) then
        return false, ferr;
    end
    local function write_list(name, list)
        list = list or {};
        f:write(string.format('profile["%s"] = T{', name));
        for i = 1, #list do
            local v = tonumber(list[i]) or 0;
            if (v ~= 0) then
                if (i > 1) then f:write(', '); end
                f:write(tostring(v));
            end
        end
        f:write('};\n');
    end
    f:write("require('common');\n\n");
    f:write("-- Auto-generated by Zzloot. Contains loot filter lists only.\n");
    f:write("local profile = T{};\n");
    if (profile_name ~= nil and tostring(profile_name) ~= "") then
        f:write(string.format("profile.ProfileName = \"%s\";\n", tostring(profile_name)));
    end
    zone_id = tonumber(zone_id) or 0;
    f:write(string.format("profile.ZoneId = %d;\n", zone_id));
    write_list('Lot',  lot_list or gSettings.Lot);
    write_list('Pass', pass_list or gSettings.Pass);
    write_list('Drop', drop_list or gSettings.Drop);
    f:write("\nreturn profile;\n");
    f:close();
    return true, nil;
end
local function current_profiles_string()
    local cp = gSettings.CurrentProfiles;
    if (type(cp) ~= 'table' or #cp == 0) then
        return '(none)';
    end
    return table.concat(cp, ', ');
end
local function zone_profile_name_for_id(zid)
    zid = tonumber(zid) or 0;
    if (zid > 0) then
        return string.format('zone%d', zid);
    end
    return 'zone0';
end
local function zone_default_profile_name()
    return zone_profile_name_for_id(get_current_zone_id() or 0);
end
profile_files_string = function(names)
    local src = names;
    if (type(src) ~= 'table') then
        src = gSettings.CurrentProfiles;
    end
    if (type(src) ~= 'table' or #src == 0) then
        return string.format('%s.lua', zone_default_profile_name());
    end
    local out = {};
    for _,name in ipairs(src) do
        local base = sanitize_profile_name(name) or tostring(name or zone_default_profile_name());
        if (tostring(base):lower() == 'default') then
            base = zone_default_profile_name();
        end
        out[#out + 1] = string.format('%s.lua', base);
    end
    return table.concat(out, ', ');
end
local function load_profile_by_name(pname)
    local path = get_profile_path(pname);
    if (path == nil) then
        return nil, 'Profile path not ready yet (player not loaded). Try again after zoning/login.';
    end
    if (not file_exists(path)) then
        return nil, string.format('List not found: %s.lua', tostring(pname));
    end
    local ok_, prof = pcall(dofile, path);
    if (not ok_) then
        return nil, 'Failed to load profile: ' .. tostring(prof);
    end
    if (type(prof) ~= 'table') then
        return nil, 'Profile file did not return a table.';
    end
    return prof, nil;
end
local function format_profile_item_list(ids)
    local out = {};
    for _,id in ipairs(ids or {}) do
        local iid = tonumber(id) or 0;
        if (iid ~= 0) then
            table.insert(out, string.format('%s [%d]', get_item_name(iid), iid));
        end
    end
    return table.concat(out, ', ');
end
local function apply_profile_tables(profile_names, profile_tables, replace_current)
    local lot  = {};
    local pass = {};
    local drop = {};
    local current_names = {};
    local seen_names = {};
    local duplicate_reports = {};
    local added_counts = { lot = 0, pass = 0, drop = 0 };
    local newly_added_ids = {};
    if (replace_current ~= true) then
        for _,v in ipairs(gSettings.Lot or {}) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then table.insert(lot, id); end
        end
        for _,v in ipairs(gSettings.Pass or {}) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then table.insert(pass, id); end
        end
        for _,v in ipairs(gSettings.Drop or {}) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then table.insert(drop, id); end
        end
        for _,name in ipairs(gSettings.CurrentProfiles or {}) do
            local pname = sanitize_profile_name(name);
            if (pname ~= nil) then
                local key = pname:lower();
                if (not seen_names[key]) then
                    seen_names[key] = true;
                    table.insert(current_names, pname);
                end
            end
        end
    end
    local function merge_into(dst, src, kind, source_name)
        local set = {};
        local skipped = {};
        for _,v in ipairs(dst) do set[tonumber(v) or 0] = true; end
        for _,v in ipairs(src or {}) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then
                if (set[id]) then
                    table.insert(skipped, id);
                else
                    table.insert(dst, id);
                    set[id] = true;
                    table.insert(newly_added_ids, id);
                    added_counts[kind] = (added_counts[kind] or 0) + 1;
                end
            end
        end
        if (#skipped > 0) then
            skipped = sort_ids_by_name(skipped);
            table.insert(duplicate_reports, {
                kind = kind,
                source = tostring(source_name or ''),
                ids = skipped,
            });
        end
    end
    for idx,prof in ipairs(profile_tables) do
        local source_name = profile_names[idx] or ('Profile' .. tostring(idx));
        merge_into(lot,  prof.Lot  or prof["Lot"]  or {}, 'lot',  source_name);
        merge_into(pass, prof.Pass or prof["Pass"] or {}, 'pass', source_name);
        merge_into(drop, prof.Drop or prof["Drop"] or {}, 'drop', source_name);
        local pname = sanitize_profile_name(source_name);
        if (pname ~= nil) then
            local key = pname:lower();
            if (not seen_names[key]) then
                seen_names[key] = true;
                table.insert(current_names, pname);
            end
        end
    end
    lot  = sort_ids_by_name(lot);
    pass = sort_ids_by_name(pass);
    drop = sort_ids_by_name(drop);
    gSettings.Lot  = T(lot);
    gSettings.Pass = T(pass);
    gSettings.Drop = T(drop);
    gSettings.CurrentProfiles = T(current_names);
    settings.save();
    rebuild_compiled();
    mark_rule_ui_recent_ids(newly_added_ids);
    invalidate_rule_ui_cache();
    return duplicate_reports, added_counts;
end
local function cmd_profiles_load(raw_names, source_tag)
    if (raw_names == nil or #raw_names == 0) then
        if (source_tag == 'auto') then
            msg(string.format('Auto: no matching profile for this zone. Current: %s. Use: /zzl load <Name>', current_profiles_string()));
        else
            err(string.format('Usage: /zzl load <Name> [<Name2> ...]   (current: %s)', current_profiles_string()));
        end
        return false;
    end
    local names = {};
    local seen = {};
    local dups = {};
    for idx,raw in ipairs(raw_names) do
        local pname = validate_profile_name(raw);
        if (pname == nil) then
            err(string.format('ERROR: Invalid profile name at position %d: %s', idx, tostring(raw or '')));
            err('Allowed characters: letters, numbers, spaces, underscores, and hyphens. Wrappers [], "", and <> are allowed.');
            return false;
        end
        local key = pname:lower();
        if (seen[key] ~= nil) then
            table.insert(dups, string.format('"%s" at positions %d and %d', pname, seen[key], idx));
        else
            seen[key] = idx;
            table.insert(names, pname);
        end
    end
    if (#dups > 0) then
        err('ERROR: Duplicate profile name(s) in load command; aborting.');
        for _,d in ipairs(dups) do
            err('  ' .. d);
        end
        return false;
    end
    local tables = {};
    for _,pname in ipairs(names) do
        local prof, perr = load_profile_by_name(pname);
        if (prof == nil) then
            err(string.format('ERROR: %s', tostring(perr)));
            err(string.format('Current: %s. Usage: /zzl load <Name> [<Name2> ...]', current_profiles_string()));
            return false;
        end
        table.insert(tables, prof);
    end
    local duplicate_reports, added_counts = apply_profile_tables(names, tables, false);
    local zid = get_current_zone_id() or 0;
    if (zid ~= 0) then
        gSettings.ZoneProfiles = gSettings.ZoneProfiles or T{};
        gSettings.ZoneProfiles[tostring(zid)] = T(gSettings.CurrentProfiles or T{});
        state.current_profile_zone_id = zid;
        settings.save();
    end
    ok(string.format('Loaded profile(s): %s', profile_files_string(gSettings.CurrentProfiles)));
    ok(string.format('Added: lot=%d pass=%d drop=%d', tonumber(added_counts.lot) or 0, tonumber(added_counts.pass) or 0, tonumber(added_counts.drop) or 0));
    for _,rep in ipairs(duplicate_reports or {}) do
        warn(string.format('Skipped duplicate %s item(s) from %s.lua: %s', tostring(rep.kind), tostring(rep.source), format_profile_item_list(rep.ids)));
    end
    return true;
end
local function ensure_default_profile()
    if (gSettings.ProfilesInitialized ~= true) then
        gSettings.ProfilesInitialized = true;
        settings.save();
    end
end
local function list_profile_names()
    local dir = get_profiles_dir();
    if (dir == nil) then
        return {};
    end
    local out = {};
    local p = io.popen('dir /b "' .. dir .. '*.lua" 2>nul');
    if (p ~= nil) then
        for line in p:lines() do
            local f = tostring(line or ''):trim();
            if (f ~= '') then
                local lower = f:lower();
                if (lower ~= 'settings.lua') then
                    local n = f:gsub('%.lua$', '');
                    n = tostring(n or ''):trim();
                    if (n ~= '') then
                        table.insert(out, n);
                    end
                end
            end
        end
        p:close();
    end
    return out;
end

local function normalize_profile_name_list(src)
    local out = {};
    local seen = {};
    for _,name in ipairs(src or {}) do
        local pname = sanitize_profile_name(name);
        if (pname ~= nil and pname ~= '') then
            local key = pname:lower();
            if (not seen[key]) then
                seen[key] = true;
                table.insert(out, pname);
            end
        end
    end
    table.sort(out, function (a, b)
        return tostring(a):lower() < tostring(b):lower();
    end);
    return out;
end
local function get_zone_profile_list(zid)
    zid = tonumber(zid) or 0;
    if (zid == 0) then return {}; end
    local zp = gSettings.ZoneProfiles;
    if (type(zp) ~= 'table') then return {}; end
    local names = zp[tostring(zid)] or zp[zid];
    if (type(names) ~= 'table') then return {}; end
    return normalize_profile_name_list(names);
end
local function set_zone_profile_list(zid, names)
    zid = tonumber(zid) or 0;
    if (zid == 0) then return; end
    gSettings.ZoneProfiles = gSettings.ZoneProfiles or T{};
    gSettings.ZoneProfiles[tostring(zid)] = T(normalize_profile_name_list(names));
end
local function ensure_zone_profile_file(zid)
    zid = tonumber(zid) or 0;
    if (zid == 0) then return nil, 'No ZoneId available.'; end
    local pname = zone_profile_name_for_id(zid);
    local path = get_profile_path(pname);
    if (path == nil) then
        return nil, 'Profile path not ready yet (player not loaded). Try again after zoning/login.';
    end
    local dir = get_profiles_dir();
    if (dir ~= nil and not ashita.fs.exists(dir)) then
        pcall(function() ashita.fs.create_dir(dir); end);
    end
    if (not file_exists(path)) then
        local ok_, ferr = write_profile_file(path, pname, zid, {}, {}, {});
        if (not ok_) then
            return nil, ferr;
        end
    end
    return pname, nil;
end
local function load_profile_tables_by_names(raw_names)
    local names = normalize_profile_name_list(raw_names or {});
    local tables = {};
    for _,pname in ipairs(names) do
        local prof, perr = load_profile_by_name(pname);
        if (prof == nil) then
            return nil, nil, string.format('ERROR: %s', tostring(perr));
        end
        table.insert(tables, prof);
    end
    return names, tables, nil;
end
local function set_current_profiles_for_zone(zid, names)
    zid = tonumber(zid) or 0;
    names = normalize_profile_name_list(names or {});
    if (#names == 0 and zid ~= 0) then
        local pname, perr = ensure_zone_profile_file(zid);
        if (pname == nil) then
            err('ERROR: Failed to create zone profile: ' .. tostring(perr));
            return false;
        end
        names = { pname };
    end
    local load_names, tables, lerr = load_profile_tables_by_names(names);
    if (lerr ~= nil) then
        err(lerr);
        return false;
    end
    apply_profile_tables(load_names, tables, true);
    if (zid ~= 0) then
        set_zone_profile_list(zid, load_names);
    end
    state.current_profile_zone_id = zid;
    clear_unsaved_runtime_changes();
    settings.save();
    request_autodrop_rescan();
    return true;
end
local function sync_zone_profile_state(force)
    local dir = get_profiles_dir();
    if (dir == nil) then return false; end
    if (not ashita.fs.exists(dir)) then
        local ok_mkdir = pcall(function() ashita.fs.create_dir(dir); end);
        if (not ok_mkdir) then
            err('ERROR: Could not create profile directory: ' .. tostring(dir));
            return false;
        end
    end
    local zid = get_current_zone_id() or 0;
    if (zid == 0) then return false; end
    if (force ~= true and tonumber(state.current_profile_zone_id) == zid) then
        return false;
    end
    local names = get_zone_profile_list(zid);
    if (#names == 0) then
        local pname, perr = ensure_zone_profile_file(zid);
        if (pname == nil) then
            err('ERROR: Failed to initialize zone profile: ' .. tostring(perr));
            return false;
        end
        names = { pname };
        set_zone_profile_list(zid, names);
        ok(string.format('Initialized zone profile: %s.lua', pname));
    end
    return set_current_profiles_for_zone(zid, names);
end
local function cmd_profiles_unload(raw_names)
    if (raw_names == nil or #raw_names == 0) then
        err(string.format('Usage: /zzl unload <Name> [<Name2> ...]   (current: %s)', current_profiles_string()));
        return false;
    end
    local remove_names = normalize_profile_name_list(raw_names);
    local remove_set = {};
    for _,name in ipairs(remove_names) do
        remove_set[name:lower()] = true;
    end
    local current = normalize_profile_name_list(gSettings.CurrentProfiles or {});
    local remaining = {};
    local removed = {};
    for _,name in ipairs(current) do
        if (remove_set[name:lower()]) then
            table.insert(removed, name);
        else
            table.insert(remaining, name);
        end
    end
    if (#removed == 0) then
        err('ERROR: None of the requested profiles are currently loaded.');
        return false;
    end
    local zid = get_current_zone_id() or 0;
    if (#remaining == 0 and zid ~= 0) then
        local pname, perr = ensure_zone_profile_file(zid);
        if (pname == nil) then
            err('ERROR: Failed to restore zone profile: ' .. tostring(perr));
            return false;
        end
        remaining = { pname };
    end
    if (not set_current_profiles_for_zone(zid, remaining)) then
        return false;
    end
    persist_runtime_state_quiet();
    ok(string.format('Unloaded profile(s): %s', profile_files_string(removed)));
    ok(string.format('Loaded profile(s): %s', profile_files_string(gSettings.CurrentProfiles)));
    return true;
end
local function find_profiles_for_zone(zid)
    zid = tonumber(zid) or 0;
    if (zid == 0) then return {}; end
    local matches = {};
    local names = list_profile_names();
    for _,raw in ipairs(names) do
        local pname = sanitize_profile_name(raw);
        if (pname ~= nil) then
            local prof, perr = load_profile_by_name(pname);
            if (prof ~= nil) then
                local pz = tonumber(prof.ZoneId) or 0;
                if (pz == zid) then
                    table.insert(matches, pname);
                end
            end
        end
    end
    table.sort(matches);
    return matches;
end
local function maybe_auto_load_for_zone()
    if (gSettings.Auto ~= true) then return; end
    sync_zone_profile_state(false);
end
local function should_autosave_zone_default_on_add()
    local zid = get_current_zone_id() or 0;
    if (zid == 0) then return false, nil, nil; end
    local current = normalize_profile_name_list(gSettings.CurrentProfiles or {});
    if (#current ~= 1) then return false, nil, nil; end
    local pname = sanitize_profile_name(current[1]);
    local zone_name = zone_profile_name_for_id(zid);
    if (pname == nil or zone_name == nil) then return false, nil, nil; end
    if (pname:lower() ~= tostring(zone_name):lower()) then
        return false, nil, nil;
    end
    local path = get_profile_path(pname);
    if (path == nil) then return false, pname, nil; end
    return true, pname, path;
end
local function autosave_zone_default_profile_quiet(silent_path_error)
    local ok_autosave, pname, path = should_autosave_zone_default_on_add();
    if (not ok_autosave) then
        if (silent_path_error ~= true and pname ~= nil and path == nil) then
            err('ERROR: Auto-save path not ready yet (player not loaded).');
        end
        return false;
    end
    local zid = get_current_zone_id() or 0;
    local lot  = sort_ids_by_name(gSettings.Lot);
    local pass = sort_ids_by_name(gSettings.Pass);
    local drop = sort_ids_by_name(gSettings.Drop);
    local ok_, ferr = write_profile_file(path, pname, zid, lot, pass, drop);
    if (not ok_) then
        err('ERROR: Failed to auto-save zone profile: ' .. tostring(ferr));
        return false;
    end
    return true;
end
persist_runtime_state_quiet = function ()
    settings.save();
    local autosaved = autosave_zone_default_profile_quiet(true);
    if (autosaved == true) then
        clear_unsaved_runtime_changes();
    end
    return (autosaved == true);
end
local function clear_current_runtime_lists(reset_profiles_to_zone_default)
    local zid = get_current_zone_id() or 0;
    local previous_profiles = normalize_profile_name_list(gSettings.CurrentProfiles or {});
    local default_name = nil;
    if (reset_profiles_to_zone_default == true and zid ~= 0) then
        local pname, perr = ensure_zone_profile_file(zid);
        if (pname == nil) then
            err('ERROR: Failed to prepare zone profile: ' .. tostring(perr));
            return false;
        end
        default_name = pname;
    end
    gSettings.Lot = T{};
    gSettings.Pass = T{};
    gSettings.Drop = T{};
    if (reset_profiles_to_zone_default == true) then
        if (default_name ~= nil) then
            gSettings.CurrentProfiles = T{ default_name };
            set_zone_profile_list(zid, gSettings.CurrentProfiles);
            state.current_profile_zone_id = zid;
        elseif (zid == 0) then
            gSettings.CurrentProfiles = T{};
            state.current_profile_zone_id = zid;
        end
    end
    settings.save();
    rebuild_compiled();
    invalidate_rule_ui_cache();
    state.inv_dirty = true;
    if (default_name ~= nil) then
        local path = get_profile_path(default_name);
        if (path == nil) then
            err('ERROR: Profile path not ready yet (player not loaded). Try again after zoning/login.');
            mark_unsaved_runtime_changes('clear');
            return false;
        end
        local ok_, ferr = write_profile_file(path, default_name, zid, {}, {}, {});
        if (not ok_) then
            err('ERROR: Failed to save cleared zone profile: ' .. tostring(ferr));
            mark_unsaved_runtime_changes('clear');
            return false;
        end
    end
    clear_unsaved_runtime_changes();
    persist_runtime_state_quiet();
    local removed_extra = math.max(0, #previous_profiles - ((default_name ~= nil) and 1 or 0));
    if (removed_extra > 0 and default_name ~= nil) then
        ok(string.format('Cleared: lot/pass/drop. Reset loaded profiles to %s.lua.', default_name));
    else
        ok('Cleared: lot/pass/drop');
    end
    return true;
end
local function cmd_profile_save(raw_name)
    local zid = get_current_zone_id() or 0;
    local pname = nil;
    if (raw_name ~= nil) then
        local perr = nil;
        pname, perr = validate_profile_name(raw_name);
        if (pname == nil) then
            err('ERROR: Invalid profile name.');
            err('Allowed characters: letters, numbers, spaces, underscores, and hyphens. Wrappers [], "", and <> are allowed.');
            return;
        end
    end
    if (pname == nil) then
        local cp = normalize_profile_name_list(gSettings.CurrentProfiles or {});
        if (#cp == 1) then
            pname = cp[1];
            msg(string.format('No name given; saving current profile: %s', tostring(pname)));
        else
            pname = zone_default_profile_name();
            if (#cp > 1) then
                msg(string.format('Multiple profiles loaded (%s). Saving current zone profile: %s.lua', current_profiles_string(), pname));
                msg("To save as a new or existing list, use: /zzl save NameOfList");
            else
                msg(string.format('No name given; saving as: %s', pname));
            end
        end
    end
    pname = sanitize_profile_name(pname);
    if (pname == nil) then
        err('ERROR: Invalid profile name.');
        err('Allowed characters: letters, numbers, spaces, underscores, and hyphens. Wrappers [], "", and <> are allowed.');
        return;
    end
    local path = get_profile_path(pname);
    if (path == nil) then
        err('ERROR: Profile path not ready yet (player not loaded). Try again after zoning/login.');
        return;
    end
    local lot  = sort_ids_by_name(gSettings.Lot);
    local pass = sort_ids_by_name(gSettings.Pass);
    local drop = sort_ids_by_name(gSettings.Drop);
    gSettings.Lot  = T(lot);
    gSettings.Pass = T(pass);
    gSettings.Drop = T(drop);
    local ok_, ferr = write_profile_file(path, pname, zid, lot, pass, drop);
    if (not ok_) then
        err('ERROR: Failed to save profile: ' .. tostring(ferr));
        return;
    end
    local current = normalize_profile_name_list(gSettings.CurrentProfiles or {});
    local seen = {};
    for _,name in ipairs(current) do seen[name:lower()] = true; end
    if (not seen[pname:lower()]) then
        table.insert(current, pname);
        current = normalize_profile_name_list(current);
        gSettings.CurrentProfiles = T(current);
    end
    if (zid ~= 0) then
        set_zone_profile_list(zid, gSettings.CurrentProfiles);
        state.current_profile_zone_id = zid;
    end
    persist_runtime_state_quiet();
    clear_unsaved_runtime_changes();
    rebuild_compiled();
    invalidate_rule_ui_cache();
    ok(string.format('Saved as %s.lua (ZoneId=%d).', pname, zid));
end
ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0) then return; end
    local cmd = args[1]:lower();
    if (cmd == '/shutdown' or cmd == '/logout' or cmd == '/quit') then
        persist_runtime_state_quiet();
        return;
    end
    if (cmd ~= '/zzl' and cmd ~= '/zzloot') then return; end
    e.blocked = true;
    ensure_default_profile();
    local sub1 = args[2] and args[2]:lower() or 'help';
    if (sub1 == 's' and tonumber(args[3]) == nil) then
        ensure_rule_ui_state();
        local cur = tonumber(gSettings.RuleUI.scale) or 100;
        echo(string.format('List UI scale: %d%%. Usage: /zzl scale 50-400 | /zzl s 150', cur));
        return;
    end
    if (sub1 == 'o' and tonumber(args[3]) == nil) then
        ensure_rule_ui_state();
        local cur = tonumber(gSettings.RuleUI.opacity) or 100;
        echo(string.format('List UI opacity: %d%%. Usage: /zzl opacity 30-100 | /zzl o 80', cur));
        return;
    end
    if (sub1 == 'help') then
        print_help(false);
        return;
	end
    if (sub1 == 'list') then
        ensure_rule_ui_state();
        local act = (args[3] and args[3]:lower()) or 'help';
        if (sub1 == 'list' and #args <= 2) then
            local v = toggle_rule_ui_visible();
            if (gSettings.Verbose == true) then
                echo(string.format('Rule list UI: %s', tostring(v)));
            end
            return;
        end
        if (act == 'toggle') then
            local v = toggle_rule_ui_visible();
            if (gSettings.Verbose == true) then
                echo(string.format('Rule list UI: %s', tostring(v)));
            end
            return;
        end
        if (act == 'show') then
            local v = tonumber(args[4]);
            if (v ~= nil) then
                v = math.floor(v + 0.5);
                if (v < 3) then v = 3; end
                if (v > 99) then v = 99; end
                state.rule_ui_session_max_rows = nil;
                gSettings.RuleUI.max_rows = v;
                state.rule_ui_scroll_y = 0;
                state.rule_ui_pending_wheel = 0;
                set_rule_ui_visible(true);
                settings.save();
                invalidate_rule_ui_cache();
                echo(string.format('Rule list visible rows: %d (saved; clamped 3-99)', v));
                return;
            end
            set_rule_ui_visible(true);
            if (gSettings.Verbose == true) then
                echo('Rule list UI: true');
            end
            return;
        end
        if (act == 'hide') then
            set_rule_ui_visible(false);
            if (gSettings.Verbose == true) then
                echo('Rule list UI: false');
            end
            return;
        end
        if (act == 'sort') then
            local mode = tostring((state.rule_ui_sort_mode) or 'alpha'):lower();
            local req = tostring(args[4] or ''):lower();
            if (req == 'alpha' or req == 'alphabetical' or req == 'default') then
                mode = 'alpha';
            elseif (req == 'recent' or req == 'last' or req == 'last-added' or req == 'lastadded') then
                mode = 'recent';
            else
                mode = (mode == 'recent') and 'alpha' or 'recent';
            end
            state.rule_ui_sort_mode = mode;
            state.rule_ui_scroll_y = 0;
            state.rule_ui_pending_wheel = 0;
            invalidate_rule_ui_cache();
            echo(string.format('Rule list sort (session): %s', (mode == 'recent') and 'last-added-on-top' or 'LOT/PASS/DROP then alphabetical'));
            return;
        end
        if (act == 'scale' or act == 's') then
            local v = tonumber(args[4]);
            if (v == nil) then
                local cur = tonumber(gSettings.RuleUI.scale) or 100;
                echo(string.format('List UI scale: %d%%. Usage: /zzl list scale 50-400 | /zzl s 150', cur));
                return;
            end
            v = math.floor(v + 0.5);
            if (v < 50) then v = 50; end
            if (v > 400) then v = 400; end
            gSettings.RuleUI.scale = v;
            state.rule_ui_measured_h = nil;
            state.rule_ui_line_h = nil;
            state.rule_ui_scroll_y = 0;
            state.rule_ui_pending_wheel = 0;
            gSettings.RuleUI.needs_center = false;
            state.rule_ui_apply_saved_pos = true;
            settings.save();
            echo(string.format('List UI scale set: %d%%', v));
            return;
        end
        if (act == 'opacity' or act == 'alpha' or act == 'o') then
            local v = tonumber(args[4]);
            if (v == nil) then
                local cur = tonumber(gSettings.RuleUI.opacity) or 100;
                echo(string.format('List UI opacity: %d%%. Usage: /zzl list opacity 30-100 | /zzl o 80', cur));
                return;
            end
            v = math.floor(v + 0.5);
            if (v < 30) then v = 30; end
            if (v > 100) then v = 100; end
            gSettings.RuleUI.opacity = v;
            settings.save();
            echo(string.format('List UI opacity set: %d%%', v));
            return;
        end
        local cur_scale = tonumber(gSettings.RuleUI.scale) or 100;
        local cur_opacity = tonumber(gSettings.RuleUI.opacity) or 100;
        local cur_visible = (gSettings.RuleUI.visible == true);
        local cur_rows = get_effective_rule_ui_max_rows();
        local cur_sort = (state.rule_ui_sort_mode == 'recent') and 'last-added-on-top' or 'LOT/PASS/DROP then alphabetical';
        echo(string.format('List UI: visible=%s pos=(%d,%d) scale=%d%% opacity=%d%% rows=%d sort=%s. Commands: /zzl list, /zzl list show|hide|toggle, /zzl list show 3-99, /zzl list sort, /zzl list scale 50-400, /zzl list opacity 30-100, /zzl help.', tostring(cur_visible), tonumber(gSettings.RuleUI.x) or 200, tonumber(gSettings.RuleUI.y) or 200, cur_scale, cur_opacity, cur_rows, cur_sort));
        return;
    end
    if (sub1 == 'scale' or (sub1 == 's' and tonumber(args[3]) ~= nil)) then
        ensure_rule_ui_state();
        local v = tonumber(args[3]);
        if (v == nil) then
            local cur = tonumber(gSettings.RuleUI.scale) or 100;
            echo(string.format('List UI scale: %d%%. Usage: /zzl scale 50-400 | /zzl s 150', cur));
            return;
        end
        v = math.floor(v + 0.5);
        if (v < 50) then v = 50; end
        if (v > 400) then v = 400; end
        gSettings.RuleUI.scale = v;
        state.rule_ui_measured_h = nil;
        state.rule_ui_line_h = nil;
        gSettings.RuleUI.needs_center = false;
        state.rule_ui_apply_saved_pos = true;
        settings.save();
        echo(string.format('List UI scale set: %d%%', v));
        return;
    end
    if (sub1 == 'opacity' or sub1 == 'alpha' or (sub1 == 'o' and tonumber(args[3]) ~= nil)) then
        ensure_rule_ui_state();
        local v = tonumber(args[3]);
        if (v == nil) then
            local cur = tonumber(gSettings.RuleUI.opacity) or 100;
            echo(string.format('List UI opacity: %d%%. Usage: /zzl opacity 30-100 | /zzl o 80', cur));
            return;
        end
        v = math.floor(v + 0.5);
        if (v < 30) then v = 30; end
        if (v > 100) then v = 100; end
        gSettings.RuleUI.opacity = v;
        settings.save();
        echo(string.format('List UI opacity set: %d%%', v));
        return;
    end
    if (sub1 == 'auto') then
        local v = bool_from_arg(args[3]);
        if (v == nil) then
            gSettings.Auto = not gSettings.Auto;
        else
            gSettings.Auto = v;
        end
        settings.save();
        rebuild_compiled();
        echo(string.format('Auto: %s', tostring(gSettings.Auto)));
        return;
    end
    if (sub1 == 'load') then
        local terms, perr = collect_profile_terms(args, 3);
        if (terms == nil) then
            if (perr == 'angle_unterminated') then
                err('Invalid profile name: missing closing ">". Example: /zzl load <My List>');
            elseif (perr == 'quote_unterminated') then
                err('Invalid profile name: missing closing quote. Example: /zzl load "My List"');
            elseif (perr == 'bracket_unterminated') then
                err('Invalid profile name: missing closing "]". Example: /zzl load [My List]');
            else
                err('Invalid profile name syntax. Use bare one-word names or wrap multi-word names in <...>, [...], or "...".');
            end
            return;
        end
        cmd_profiles_load(terms, 'manual');
        return;
    end
    if (sub1 == 'unload') then
        local terms, perr = collect_profile_terms(args, 3);
        if (terms == nil) then
            if (perr == 'angle_unterminated') then
                err('Invalid profile name: missing closing ">". Example: /zzl unload <My List>');
            elseif (perr == 'quote_unterminated') then
                err('Invalid profile name: missing closing quote. Example: /zzl unload "My List"');
            elseif (perr == 'bracket_unterminated') then
                err('Invalid profile name: missing closing "]". Example: /zzl unload [My List]');
            else
                err('Invalid profile name syntax. Use bare one-word names or wrap multi-word names in <...>, [...], or "...".');
            end
            return;
        end
        cmd_profiles_unload(terms);
        return;
    end
    if (sub1 == 'save') then
        local terms, perr = collect_profile_terms(args, 3);
        if (terms == nil) then
            if (perr == 'angle_unterminated') then
                err('Invalid profile name: missing closing ">". Example: /zzl save <My List>');
            elseif (perr == 'quote_unterminated') then
                err('Invalid profile name: missing closing quote. Example: /zzl save "My List"');
            elseif (perr == 'bracket_unterminated') then
                err('Invalid profile name: missing closing "]". Example: /zzl save [My List]');
            else
                err('Invalid profile name syntax. Use a bare one-word name or wrap the name in <...>, [...], or "...".');
            end
            return;
        end
        if (terms ~= nil and #terms > 1) then
            err('Save accepts one profile name at a time. Use /zzl save <Name>, /zzl save [Name], or /zzl save "Name".');
            return;
        end
        if (terms ~= nil and #terms > 0) then
            cmd_profile_save(terms[1]);
        else
            cmd_profile_save(nil);
        end
        return;
    end
    if (sub1 == 'on' or sub1 == 'off') then
        gSettings.Enabled = (sub1 == 'on');
        settings.save();
        rebuild_compiled();
        echo(string.format('Enabled: %s', tostring(gSettings.Enabled)));
        return;
    end
    if (sub1 == 'zone') then
        local zid = get_current_zone_id();
        if (zid == nil) then
            echo('Zone id not available yet.');
            return;
        end
        local act = (args[3] and tostring(args[3]):lower()) or '';
        act = act:trim();
        local function get_ignore_arr()
            local arr = {};
            local src = gSettings.IgnoreZones or gSettings.PauseZones or {};
            if (type(src) == 'table') then
                for _,v in ipairs(src) do
                    local n = tonumber(v) or 0;
                    if (n ~= 0) then table.insert(arr, n); end
                end
            end
            table.sort(arr);
            return arr;
        end
        local function save_ignore_arr(arr)
            gSettings.IgnoreZones = T(arr);
            settings.save();
            rebuild_compiled();
        end
        if (act == '' or act == 'id') then
            echo(string.format('ZoneId: %d%s', zid, is_ignored_zone() and ' (ignored)' or ''));
            return;
        end
        if (act == '+' or act == '+i' or act == 'add' or act == 'addi' or act == 'ignore') then
            local arr = get_ignore_arr();
            local set = {};
            for _,v in ipairs(arr) do set[v] = true; end
            if (not set[zid]) then table.insert(arr, zid); end
            save_ignore_arr(arr);
            echo(string.format('Added ignore zone: %d', zid));
            return;
        end
        if (act == '-' or act == '-i' or act == 'remove' or act == 'removei' or act == 'unignore') then
            local arr = get_ignore_arr();
            local out = {};
            for _,v in ipairs(arr) do
                if (v ~= zid) then table.insert(out, v); end
            end
            save_ignore_arr(out);
            echo(string.format('Removed ignore zone: %d', zid));
            return;
        end
        if (act == 'list') then
            local arr = get_ignore_arr();
            echo(string.format('Ignore zones: %s', (#arr > 0) and table.concat(arr, ', ') or '(none)'));
            return;
        end
        echo('Invalid zone command. Use: /zzl zone +i | /zzl zone -i | /zzl zone list');
        return;
    end
    if (sub1 == 'reset') then
        local keep_lot = T(gSettings.Lot or T{});
        local keep_pass = T(gSettings.Pass or T{});
        local keep_drop = T(gSettings.Drop or T{});
        local keep_current_profiles = T(gSettings.CurrentProfiles or T{});
        local keep_zone_profiles = T(gSettings.ZoneProfiles or T{});
        local keep_ignore_zones = T(gSettings.IgnoreZones or T{});
        local keep_profiles_init = (gSettings.ProfilesInitialized == true);
        local keep_ignore_init = (gSettings.IgnoreZonesInitialized ~= false);
        local keep_airship_init = (gSettings.AirshipIgnoreZonesInitialized ~= false);
        gSettings.AutoStack = defaults.AutoStack;
        gSettings.AutoDrop = defaults.AutoDrop;
        gSettings.Delay = defaults.Delay;
        gSettings.Verbose = defaults.Verbose;
        gSettings.Enabled = defaults.Enabled;
        gSettings.Auto = defaults.Auto;
        gSettings.Lot = keep_lot;
        gSettings.Pass = keep_pass;
        gSettings.Drop = keep_drop;
        gSettings.CurrentProfiles = keep_current_profiles;
        gSettings.ZoneProfiles = keep_zone_profiles;
        gSettings.IgnoreZones = keep_ignore_zones;
        gSettings.ProfilesInitialized = keep_profiles_init;
        gSettings.IgnoreZonesInitialized = keep_ignore_init;
        gSettings.AirshipIgnoreZonesInitialized = keep_airship_init;
        gSettings.RuleUI = T(defaults.RuleUI);
        ensure_rule_ui_state();
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        state.rule_ui_pending_action = nil;
        state.rule_ui_apply_saved_pos = true;
        state.rule_ui_measured_h = nil;
        state.rule_ui_line_h = nil;
        reset_rule_ui_session_state();
        rebuild_compiled();
        settings.save();
        echo('Addon settings reset to defaults. Preserved lists/profiles/ignore zones.');
        return;
    end

    if (sub1 == 'autodrop' or sub1 == 'autostack' or sub1 == 'verbose') then
        local v = bool_from_arg(args[3]);
        if (sub1 == 'autodrop') then set_bool_setting('AutoDrop', v);
        elseif (sub1 == 'autostack') then set_bool_setting('AutoStack', v);
        elseif (sub1 == 'verbose') then set_bool_setting('Verbose', v);
        end
        return;
    end
    if (sub1 == 'delay') then
        local v = tonumber(args[3]);
        if (v == nil) then
            ok(string.format('Delay: %.2f. Usage: /zzl delay <seconds>', tonumber(gSettings.Delay) or 0));
            return;
        end
        if (v < 0) then v = 0; end
        gSettings.Delay = v;
        settings.save();
        ok(string.format('Delay: %.2f', gSettings.Delay));
        return;
    end
    if (sub1 == 'lotall' or sub1 == 'passall' or sub1 == 'done') then
        local cumulative = 0;
        for i = 0, 9 do
            local id = tonumber(state.pool_ids[i]) or 0;
            if (id ~= 0) then
                local skip = (sub1 == 'done' and state.pool_status[i] ~= 0);
                if (not skip) then
                    cumulative = cumulative + random_delay();
                    if (sub1 == 'lotall') then
                        enqueue_action('lot', function(s) inject_lot(s); end, {i}, cumulative);
                    else
                        enqueue_action('pass', function(s) inject_pass(s); end, {i}, cumulative);
                    end
                end
            end
        end
        return;
    end
    if (sub1 == 'clearall' or sub1 == 'clear') then
        clear_current_runtime_lists(true);
        return;
    end

    local function is_rule_token(v)
        v = list_name_from_mode(v);
        return (v == 'lot' or v == 'pass' or v == 'drop');
    end
    local function is_action_token(v)
        v = action_name_from_mode(v);
        return (v == 'add' or v == 'remove');
    end

    local which = nil;
    local action = nil;
    local start_idx = nil;

    local sub2_raw = args[3];
    local sub2_rule = list_name_from_mode(sub2_raw or '');
    local sub2_action = action_name_from_mode(sub2_raw or '');

    if (is_rule_token(sub1)) then
        which = list_name_from_mode(sub1);
        if (sub2_action == 'add' or sub2_action == 'remove') then
            action = sub2_action;
            start_idx = 4;
        elseif (sub2_rule == 'list' or sub2_rule == 'clear') then
            action = sub2_rule;
            start_idx = nil;
        elseif (sub2_raw ~= nil) then
            action = 'add';
            start_idx = 3;
        end
    elseif (is_action_token(sub1)) then
        action = action_name_from_mode(sub1);
        if (is_rule_token(sub2_raw)) then
            which = list_name_from_mode(sub2_raw);
            start_idx = 4;
        elseif (action == 'remove') then
            start_idx = 3;
        else
            err('Missing rule. Use l/lot, p/pass, or d/drop. Example: /zzl + p "Valor Surcoat"');
            return;
        end
    else
        err('Unknown command. Try /zzl help.');
        return;
    end

    if (which ~= nil and action == 'list') then
        local list_ref = get_list_ref(which);
        local out = {};
        for _,id in ipairs(list_ref or T{}) do
            table.insert(out, get_item_name(id));
        end
        msg(string.format('%s list: %s', which, (#out > 0) and table.concat(out, ', ') or '(empty)'));
        return;
    end
    if (which ~= nil and action == 'clear') then
        if (which == 'lot') then gSettings.Lot = T{};
        elseif (which == 'pass') then gSettings.Pass = T{};
        else gSettings.Drop = T{}; end
        settings.save();
        rebuild_compiled();
        invalidate_rule_ui_cache();
        if (autosave_zone_default_profile_quiet() == true) then
            clear_unsaved_runtime_changes();
        else
            mark_unsaved_runtime_changes(which .. '_clear');
        end
        ok(string.format('Cleared: %s', which));
        return;
    end

    if (action ~= 'add' and action ~= 'remove') then
        err('Invalid rule command. Try /zzl help.');
        return;
    end
    if (action == 'add' and which == nil) then
        err('Missing rule. Use l/lot, p/pass, or d/drop. Example: /zzl + p "Valor Surcoat"');
        return;
    end
    if (start_idx == nil) then
        err('Missing item name or id.');
        return;
    end

    local show_autodrop_hint = false;
    if (args[start_idx] and args[start_idx]:lower() == 'global') then
        warn('Note: "global" is not supported in Ashita port (no built-in IPC). Applying locally only.');
        start_idx = start_idx + 1;
    end
    local term, term_state = parse_term_tokens(args, start_idx);
    local example_rule = which or 'p';
    if (term == nil) then
        if (term_state == 'angle_unterminated') then
            err('Invalid name: missing closing ">". Example: /zzl ' .. example_rule .. ' <Revival Root>');
        elseif (term_state == 'quote_unterminated') then
            err('Invalid name: missing closing quote. Example: /zzl ' .. example_rule .. ' "Revival Root"');
        elseif (term_state == 'needs_wrapping') then
            err('Multi-word names must be wrapped in <...> or "...". Example: /zzl ' .. example_rule .. ' "Valor Surcoat"');
        else
            err('Missing item name or id.');
        end
        return;
    end
    if (tostring(term):trim() == '') then
        err('Missing item name or id.');
        return;
    end
    local ids = resolve_ids(term);
    if (ids == nil or #ids == 0) then
        err('Item not found: ' .. term .. '. Check spelling or use the numeric item ID.');
        return;
    end

    if (action == 'add') then
        local lot_set = {};
        local pass_set = {};
        local drop_set = {};
        for _,v in ipairs(gSettings.Lot or T{}) do lot_set[tonumber(v) or 0] = true; end
        for _,v in ipairs(gSettings.Pass or T{}) do pass_set[tonumber(v) or 0] = true; end
        for _,v in ipairs(gSettings.Drop or T{}) do drop_set[tonumber(v) or 0] = true; end
        local changed_any = false;
        local changed_for_autodrop_hint = false;
        local recent_changed = {};
        for _,v in ipairs(ids) do
            local id = tonumber(v) or 0;
            if (id ~= 0) then
                local item_name = get_item_name(id);
                local had_lot = (lot_set[id] == true);
                local had_pass = (pass_set[id] == true);
                local had_drop = (drop_set[id] == true);
                local already = ((which == 'lot' and had_lot) or (which == 'pass' and had_pass) or (which == 'drop' and had_drop));
                local changed = false;
                if (which == 'lot') then
                    if (had_pass) then pass_set[id] = nil; changed = true; end
                    if (not had_lot) then lot_set[id] = true; changed = true; end
                elseif (which == 'pass') then
                    if (had_lot) then lot_set[id] = nil; changed = true; end
                    if (not had_pass) then pass_set[id] = true; changed = true; end
                else
                    if (not had_drop) then drop_set[id] = true; changed = true; end
                    if (gSettings.AutoDrop ~= true) then changed_for_autodrop_hint = true; end
                end
                if (changed) then
                    changed_any = true;
                    table.insert(recent_changed, id);
                    if ((which == 'lot' and had_pass) or (which == 'pass' and had_lot)) then
                        ok(string.format('%s was already set to %s, so it was changed to %s.', item_name, had_pass and 'PASS' or 'LOT', rule_name_upper(which)));
                    elseif (already) then
                        ok(string.format('No change: %s is already in the %s list.', item_name, rule_name_upper(which)));
                    else
                        ok(string.format('Added to %s: %s', rule_name_upper(which), item_name));
                    end
                else
                    ok(string.format('No change: %s is already in the %s list.', item_name, rule_name_upper(which)));
                end
            end
        end
        gSettings.Lot = T(set_to_sorted_id_list(lot_set));
        gSettings.Pass = T(set_to_sorted_id_list(pass_set));
        gSettings.Drop = T(set_to_sorted_id_list(drop_set));
        mark_rule_ui_recent_ids(recent_changed);
        if (changed_any) then
            if (autosave_zone_default_profile_quiet() == true) then
                clear_unsaved_runtime_changes();
            else
                mark_unsaved_runtime_changes(which .. '_add');
            end
        end
        if (changed_for_autodrop_hint) then
            show_autodrop_hint = true;
        end
        settings.save();
        rebuild_compiled();
        invalidate_rule_ui_cache();
        if (which == 'drop') then
            request_autodrop_rescan();
            if (show_autodrop_hint) then
                msg('AutoDrop is off. Enable it with /zzl autodrop on if you want matching inventory items to be dropped automatically.');
            end
        else
            state.inv_dirty = true;
            rescan_current_pool_rules(recent_changed);
        end
        return;
    end

    local removed_total = 0;
    local changed_lists = {};
    local function remove_from_list(name, list)
        local before = #(list or T{});
        local out = sort_ids_by_name(remove_ids(list or T{}, ids));
        local removed = before - #out;
        if (removed > 0) then
            removed_total = removed_total + removed;
            table.insert(changed_lists, name);
        end
        return out;
    end
    if (which == nil) then
        gSettings.Lot = T(remove_from_list('LOT', gSettings.Lot));
        gSettings.Pass = T(remove_from_list('PASS', gSettings.Pass));
        gSettings.Drop = T(remove_from_list('DROP', gSettings.Drop));
    else
        local out = nil;
        if (which == 'lot') then
            out = remove_from_list('LOT', gSettings.Lot);
            gSettings.Lot = T(out);
        elseif (which == 'pass') then
            out = remove_from_list('PASS', gSettings.Pass);
            gSettings.Pass = T(out);
        else
            out = remove_from_list('DROP', gSettings.Drop);
            gSettings.Drop = T(out);
        end
    end
    if (removed_total == 0) then
        err('Item not found in matching rule list(s): ' .. term);
        return;
    end
    settings.save();
    rebuild_compiled();
    invalidate_rule_ui_cache();
    if (autosave_zone_default_profile_quiet() == true) then
        clear_unsaved_runtime_changes();
    else
        mark_unsaved_runtime_changes((which or 'all') .. '_remove');
    end
    rescan_current_pool_rules(ids);
    request_autodrop_rescan();
    state.inv_dirty = true;
    ok(string.format('Removed from %s: %s', table.concat(changed_lists, '+'), term));
    return;
end);
local function get_mouse_wheel_steps(e)
    local delta = tonumber(e and e.delta) or 0;
    if (delta == 0 and e ~= nil) then
        local wp = tonumber(e.wparam) or 0;
        delta = math.floor(wp / 65536);
        if (delta >= 32768) then
            delta = delta - 65536;
        end
    end
    if (delta < 0) then return -1; end
    if (delta > 0) then return 1; end
    return 0;
end
local function is_mouse_click_message(message)
    return message == 513 or message == 514 or message == 515
        or message == 516 or message == 517 or message == 518
        or message == 519 or message == 520 or message == 521;
end
local function get_effective_mouse_xy(e, message)
    local mx = tonumber(e and e.x);
    local my = tonumber(e and e.y);
    if (message == 522) then -- WM_MOUSEWHEEL often arrives without reliable x/y in this binding
        if ((mx == nil or my == nil or ((mx == 0 and my == 0) and ((tonumber(state.mouse_x) or 0) ~= 0 or (tonumber(state.mouse_y) or 0) ~= 0)))) then
            mx = tonumber(state.mouse_x) or mx or 0;
            my = tonumber(state.mouse_y) or my or 0;
        end
    end
    mx = tonumber(mx) or 0;
    my = tonumber(my) or 0;
    if (message ~= 522 or mx ~= 0 or my ~= 0) then
        state.mouse_x = mx;
        state.mouse_y = my;
    end
    return mx, my;
end
local function update_shift_state(e)
    if (e == nil) then
        return;
    end
    local wparam = tonumber(e.wparam) or 0;
    if (wparam ~= 0x10 and wparam ~= 0xA0 and wparam ~= 0xA1) then
        return;
    end
    if (bit ~= nil and e.lparam ~= nil) then
        local released = bit.band(tonumber(e.lparam) or 0, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10);
        state.shift_down = not released;
        return;
    end
    state.shift_down = query_shift_state();
end
ashita.events.register('key', 'zzloot_key_cb', function (e)
    update_shift_state(e);
end);
ashita.events.register('mouse', 'zzloot_mouse_cb', function (e)
    ensure_rule_ui_state();
    if (gSettings.RuleUI == nil or gSettings.RuleUI.visible ~= true) then
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        state.rule_ui_recover_unreachable_since = nil;
        return;
    end
    local message = tonumber(e.message) or 0;
    if (message == 513) then
        state.left_mouse_down = true;
    elseif (message == 514) then
        state.left_mouse_down = false;
    end
    local mx, my = get_effective_mouse_xy(e, message);
    local shift_down = query_shift_state();
    local ir = state.rule_ui_interactive or {};
    local over_button = rule_ui_hits_button(mx, my);
    local over_scrollbar = rule_ui_hits_scrollbar(mx, my);
    local over_window = rule_ui_hits_window(mx, my);
    if (state.rule_ui_dragging == true) then
        if (message == 512) then -- WM_MOUSEMOVE
            gSettings.RuleUI.x = math.floor(mx - (state.rule_ui_drag_offset_x or 0) + 0.5);
            gSettings.RuleUI.y = math.floor(my - (state.rule_ui_drag_offset_y or 0) + 0.5);
            state.rule_ui_apply_saved_pos = true;
            rule_ui_mark_pos_dirty(os.clock());
            e.blocked = true;
            return;
        end
        if (message == 514) then -- WM_LBUTTONUP
            state.rule_ui_dragging = false;
            state.rule_ui_recover_unreachable_since = nil;
            settings.save();
            e.blocked = true;
            return;
        end
    end
    if (state.rule_ui_button_capture ~= nil) then
        if (message == 512) then
            e.blocked = true;
            return;
        end
        if (message == 514) then
            local captured = state.rule_ui_button_capture;
            state.rule_ui_button_capture = nil;
            if ((captured == 'toggle_min' and rect_contains(ir.min_button, mx, my))
                    or (captured == 'close' and rect_contains(ir.close_button, mx, my))) then
                state.rule_ui_pending_action = captured;
            end
            state.rule_ui_recover_unreachable_since = nil;
            e.blocked = true;
            return;
        end
    end
    if (message == 513) then -- WM_LBUTTONDOWN
        if (rect_contains(ir.min_button, mx, my)) then
            state.rule_ui_button_capture = 'toggle_min';
            e.blocked = true;
            return;
        end
        if (rect_contains(ir.close_button, mx, my)) then
            state.rule_ui_button_capture = 'close';
            e.blocked = true;
            return;
        end
        if (shift_down and over_window and not over_button) then
            local rect = state.rule_ui_rect;
            if (rect ~= nil) then
                state.rule_ui_dragging = true;
                state.rule_ui_drag_offset_x = mx - rect.x;
                state.rule_ui_drag_offset_y = my - rect.y;
                e.blocked = true;
                return;
            end
        end
    end
    if (message == 522) then
        return;
    end
    if (over_scrollbar and is_mouse_click_message(message)) then
        e.blocked = true;
        return;
    end
end);
ashita.events.register('d3d_present', 'd3d_present_ui_cb', function ()
    if (not is_player_logged_in()) then
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        state.rule_ui_recover_unreachable_since = nil;
        return;
    end
    sync_zone_profile_state(false);
    local zid_now = get_current_zone_id() or 0;
    if (gSettings.RuleUI ~= nil and gSettings.RuleUI.visible == true and zid_now ~= 0 and tonumber(state.current_profile_zone_id) == zid_now) then
        rule_ui_recover_if_buttons_unreachable(query_shift_state(), query_left_mouse_state());
    else
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        state.rule_ui_recover_unreachable_since = nil;
    end
    render_rule_list_ui();
end);
ashita.events.register('load', 'load_cb', function ()
    seed_default_airship_ignore_zones();
    rebuild_compiled();
    ensure_default_profile();
    ensure_rule_ui_state();
    reset_rule_ui_session_state();
    sync_zone_profile_state(true);
    print(chat.header('Addons'):append(chat.message('/zzl help for more info.')));
end);
ashita.events.register('unload', 'unload_cb', function ()
    persist_runtime_state_quiet();
end);
ashita.events.register('text_in', 'text_in_cb', function (e)
    if (e == nil or e.injected) then return; end
    local reason = classify_lot_rejection_message(e.message);
    if (reason == nil) then return; end
    local itemId = select(1, consume_recent_lot_attempt(6.0));
    if ((tonumber(itemId) or 0) == 0) then return; end
    mark_lot_item_rejected_for_current_pool(itemId, reason);
end);
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.id == 0x00A) then
        local autosaved = persist_runtime_state_quiet();
        if (state.runtime_profile_dirty == true and autosaved ~= true) then
            warn('List changes from the previous zone were not saved. Use /zzl save before zoning if you want to keep edits.');
        end
        clear_unsaved_runtime_changes();
        clear_rule_ui_interactive_rects();
        state.rule_ui_dragging = false;
        state.rule_ui_button_capture = nil;
        state.rule_ui_pending_action = nil;
        for i = 0, 9 do
            state.pool_ids[i] = 0;
            state.pool_status[i] = 0;
        end
        state.actions = {};
        state.inv_dirty = false;
        state.drop_pending = false;
        state.pool_empty_since = os.clock();
        state.auto_zone_id = 0;
        state.auto_attempted = false;
        state.current_profile_zone_id = -1;
        state.lot_skip_notified = {};
        state.lot_rejected_current_pool = {};
        state.recent_lot_attempts = {};
        state.deferred_warns = {};
        return;
    end
    if (e.id == 0x0D2) then
        local itemId = struct.unpack('H', e.data, 0x10 + 1);
        local slot   = struct.unpack('B', e.data, 0x14 + 1);
        local oldItemId = tonumber(state.pool_ids[slot]) or 0;
        local freshItem = ((tonumber(itemId) or 0) ~= 0) and (not pool_contains_item_except_slot(itemId, slot));
        state.pool_ids[slot] = tonumber(itemId) or 0;
        state.pool_status[slot] = 0;
        if (oldItemId ~= 0 and oldItemId ~= (tonumber(itemId) or 0)) then
            clear_lot_rejection_if_item_left_pool(oldItemId);
        end
        if (freshItem) then
            state.lot_skip_notified[tonumber(itemId) or 0] = nil;
            state.lot_rejected_current_pool[tonumber(itemId) or 0] = nil;
        end
        update_pool_empty_state();
        maybe_auto_load_for_zone();
        decide_pool_slot(slot, itemId);
        return;
    end
    if (e.id == 0x0D3) then
        local slot = struct.unpack('B', e.data, 0x14 + 1);
        local drop = struct.unpack('B', e.data, 0x15 + 1);
        if (drop ~= 0) then
            local oldItemId = tonumber(state.pool_ids[slot]) or 0;
            state.pool_ids[slot] = 0;
            state.pool_status[slot] = 0;
            if (oldItemId ~= 0) then
                clear_lot_rejection_if_item_left_pool(oldItemId);
            end
        end
        update_pool_empty_state();
        if (pool_is_empty()) then
            state.lot_skip_notified = {};
            state.lot_rejected_current_pool = {};
            state.recent_lot_attempts = {};
        end
        return;
    end
    if (e.id == 0x01F or e.id == 0x020 or e.id == 0x01E) then
        if (is_active()) then
            state.inv_dirty = true;
        end
        return;
    end
end);
ashita.events.register('packet_out', 'packet_out_cb', function (e)
    if (e.id == 0x015) then
        prune_recent_lot_attempts(6.0);
        if (can_network()) then
            process_actions();
            handle_inventory_dirty();
            flush_deferred_warns();
        end
        return;
    end
    if (e.id == 0x041) then
        local slot = struct.unpack('B', e.data, 0x04 + 1);
        state.pool_status[slot] = 1;
        return;
    end
    if (e.id == 0x042) then
        local slot = struct.unpack('B', e.data, 0x04 + 1);
        state.pool_status[slot] = 2;
        return;
    end
end);
