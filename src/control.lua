local GUI, SHORTCUT = "cssa_frame", "cssa_open"
local SCAN_ALL, SCAN_CURRENT, SCAN_SELECTED = "cssa_scan", "cssa_scan_current", "cssa_scan_selected_surface"
local SCAN_AREA, SCAN_TOOL, PICKER, CLOSE = "cssa_scan_area", "cssa-scan-area-tool", "cssa_surface_picker", "cssa_close"
local SELECT_PREFIX = "cssa_select_"
local CONFIRM_FRAME, CONFIRM_CONTINUE, CONFIRM_CANCEL = "cssa_scan_confirm", "cssa_scan_confirm_continue", "cssa_scan_confirm_cancel"
local LARGE_SCAN_THRESHOLD = 25000
local pending_scan_entities = {}

local input_flags = {
  "circuit_enable_disable", "circuit_set_filters", "circuit_set_recipe", "circuit_set_stack_size",
  "circuit_set_signal", "circuit_set_priority", "circuit_set_train_limit", "circuit_set_trains_limit",
  "circuit_set_requests", "circuit_set_requests_from_buffers",
}
local output_flags = {
  "circuit_read_ingredients", "circuit_read_working", "circuit_read_contents", "circuit_read_hand_contents",
  "circuit_read_transfers", "read_contents", "read_resources", "read_hand_contents", "read_charge",
  "read_sensor", "read_robot_stats", "read_logistics", "read_belt_contents", "read_train_id",
  "read_stopped_train", "read_trains_count", "read_trains_limit", "read_temperature", "read_pollution",
  "read_ingredients", "read_working", "read_transfers", "read_contents_pulse", "read_signal",
}

local function safe_get(object, key)
  if not object then return nil end
  local ok, value = pcall(function() return object[key] end)
  if ok then return value end
end
local function active_flags(behavior, keys)
  local out = {}
  for _, key in ipairs(keys) do if safe_get(behavior, key) == true then out[#out + 1] = key end end
  return out
end
local function get_networks(behavior, key)
  local v = safe_get(behavior, key)
  if type(v) ~= "table" then return nil end
  return {red = v.red == true, green = v.green == true}
end
local function classify(entity)
  if not entity or not entity.valid then return nil end
  local getter = safe_get(entity, "get_control_behavior")
  if type(getter) ~= "function" then return nil end
  local ok, behavior = pcall(function() return entity.get_control_behavior() end)
  if not ok or not behavior then return nil end
  local inputs, outputs = active_flags(behavior, input_flags), active_flags(behavior, output_flags)
  if #inputs == 0 or #outputs == 0 then return nil end
  local ins, outs = get_networks(behavior, "input_networks"), get_networks(behavior, "output_networks")
  local overlap = {}
  if ins and outs then
    if ins.red and outs.red then overlap[#overlap + 1] = "red" end
    if ins.green and outs.green then overlap[#overlap + 1] = "green" end
    -- Either red-in/green-out or green-in/red-out is already segregated.
    -- Only keep entities that read and write on at least one shared color.
    if #overlap == 0 then return nil end
  end
  return {entity=entity, surface=entity.surface.name, x=math.floor(entity.position.x*100+0.5)/100,
    y=math.floor(entity.position.y*100+0.5)/100, name=entity.name, kind=safe_get(entity,"type") or "unknown",
    inputs=inputs, outputs=outputs, input_networks=ins, output_networks=outs, overlap=overlap}
end
local function sort_results(results)
  table.sort(results, function(a,b)
    if a.surface ~= b.surface then return a.surface < b.surface end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return results
end
local function scan_entities(entities)
  local out = {}
  for _, entity in pairs(entities or {}) do local f=classify(entity); if f then out[#out+1]=f end end
  return sort_results(out)
end
local function scan_entity_lists(entity_lists)
  local out = {}
  for _, entities in pairs(entity_lists or {}) do
    for _, f in ipairs(scan_entities(entities)) do out[#out+1]=f end
  end
  return sort_results(out)
end
local function scan_surfaces(surfaces)
  local entity_lists = {}
  for _, surface in pairs(surfaces or {}) do
    if surface and surface.valid then entity_lists[#entity_lists+1] = surface.find_entities() end
  end
  return scan_entity_lists(entity_lists)
end
local function all_surfaces()
  local out={}; for _, s in pairs(game.surfaces) do out[#out+1]=s end
  table.sort(out,function(a,b) return a.name < b.name end); return out
end
local function clear_frame(player) local f=player.gui.screen[GUI]; if f and f.valid then f.destroy() end end
-- Remove the legacy top-GUI button left behind by earlier versions. GUI elements
-- can survive a mod update even after the code that created them is removed.
local function remove_legacy_button(player)
  local function visit(parent)
    if not parent or not parent.valid then return end
    for _, child in pairs(parent.children) do
      if child.valid then
        local caption = safe_get(child, "caption")
        local name = safe_get(child, "name")
        if name == "cssa_open" or name == "cssa_button" or name == "circuit_self_subtraction_audit_button"
          or (type(caption) == "string" and caption == "Circuit Audit") then
          child.destroy()
        else
          visit(child)
        end
      end
    end
  end
  visit(player.gui.top)
end
local function network_text(v)
  if not v then return "not exposed by this control behavior" end
  local t={}; if v.red then t[#t+1]="red" end; if v.green then t[#t+1]="green" end
  return #t>0 and table.concat(t,", ") or "none selected"
end
local function draw_details(player)
  local frame=player.gui.screen[GUI]; if not frame or not frame.valid then return end
  local body=frame.body; if not body or not body.valid or not body.split or not body.split.valid then return end
  local split=body.split; local old=split.details; if old and old.valid then old.destroy() end
  local d=split.add{type="flow",name="details",direction="vertical"}; d.style.width=410
  local state=storage.cssa[player.index]; local f=state.selected and state.results[state.selected]
  if not f then d.add{type="label",caption="Select an entity to inspect its active flags and network selections."}; return end
  d.add{type="label",caption=f.name .. " — " .. f.surface}
  d.add{type="label",caption=("Position: (%s, %s)"):format(f.x,f.y)}
  d.add{type="label",caption="Entity type: " .. f.kind}
  d.add{type="label",caption="Active input flags: " .. table.concat(f.inputs,", ")}
  d.add{type="label",caption="Active output flags: " .. table.concat(f.outputs,", ")}
  d.add{type="label",caption="Configured input networks: " .. network_text(f.input_networks)}
  d.add{type="label",caption="Configured output networks: " .. network_text(f.output_networks)}
  if f.input_networks and f.output_networks then
    d.add{type="label",caption="Colors selected for both input and output: " .. (#f.overlap>0 and table.concat(f.overlap,", ") or "none")}
  else d.add{type="label",caption="Input/output network overlap: unavailable for this behavior"} end
  d.add{type="label",caption="Configuration evidence only; this is not a diagnosis or repair recommendation."}
  d.add{type="button",name="cssa_locate",caption="View entity (remote view)"}
end
local function draw_results(player)
  local frame=player.gui.screen[GUI]; if not frame or not frame.valid then return end
  local state=storage.cssa[player.index]; local body=frame.body; if body and body.valid then body.destroy() end
  body=frame.add{type="flow",name="body",direction="vertical"}; body.style.maximal_width=1000
  body.add{type="label",caption=("Matching entities: %d"):format(#state.results),style="heading_2_label"}
  body.add{type="label",caption="Entities with recognized active circuit input AND output flags."}
  body.add{type="label",caption="Read-only audit: no repair recommendations or configuration changes."}
  local actions=body.add{type="flow",direction="horizontal"}
  actions.add{type="button",name=SCAN_ALL,caption="Scan all surfaces"}
  actions.add{type="button",name=SCAN_CURRENT,caption="Scan current surface"}
  local names, selected_index={},1
  for i,s in ipairs(all_surfaces()) do names[#names+1]=s.name; if state.scan_surface_name==s.name then selected_index=i end end
  if #names>0 then actions.add{type="drop-down",name=PICKER,items=names,selected_index=selected_index}; actions.add{type="button",name=SCAN_SELECTED,caption="Scan selected surface"} end
  actions.add{type="button",name=SCAN_AREA,caption="Scan area…"}
  local split=body.add{type="flow",name="split",direction="horizontal"}; split.style.horizontal_spacing=12
  local list=split.add{type="scroll-pane",name="list"}; list.style.width=470; list.style.height=390; list.style.maximal_height=390
  for i,f in ipairs(state.results) do
    local selected = state.selected == i
    local row = list.add{type="button",name=SELECT_PREFIX..i,caption=f.name .. "  [" .. f.surface .. "]  (" .. f.x .. ", " .. f.y .. ")",tags={finding_index=i},style="list_box_item"}
    if selected then
      row.style.font_color = {r=1, g=0.82, b=0.25}
      row.style.font = "default-bold"
    end
  end
  draw_details(player)
end
local function open_gui(player)
  clear_frame(player)
  local f=player.gui.screen.add{type="frame",name=GUI,direction="vertical"}; f.auto_center=true; f.style.width=1000
  local titlebar=f.add{type="flow",name="titlebar",direction="horizontal"}
  titlebar.drag_target=f
  titlebar.add{type="label",name="title",caption="Circuit Self-Subtraction Audit",style="frame_title",ignored_by_interaction=true}
  local drag_space=titlebar.add{type="empty-widget",name="drag_space",style="draggable_space_header"}
  drag_space.style.horizontally_stretchable=true
  drag_space.style.height=24
  drag_space.drag_target=f
  titlebar.add{type="sprite-button",name=CLOSE,style="frame_action_button",sprite="utility/close",tooltip={"gui.close"}}
  f.add{type="flow",name="body",direction="vertical"}
  storage.cssa[player.index]=storage.cssa[player.index] or {results={},selected=nil}; draw_results(player)
end
local function set_results(player, results, scope)
  local state=storage.cssa[player.index]; state.results=results; state.selected=nil; state.scan_scope=scope
  draw_results(player); player.print(("Circuit audit complete (%s): %d matching entities."):format(scope,#results))
end
local function count_and_scan_surfaces(player, surfaces, scope, surface_name)
  local entity_lists, count = {}, 0
  for _, surface in ipairs(surfaces or {}) do
    if surface and surface.valid then
      local entities = surface.find_entities()
      entity_lists[#entity_lists+1] = entities
      count = count + #entities
    end
  end
  if count >= LARGE_SCAN_THRESHOLD then
    pending_scan_entities[player.index] = {entity_lists=entity_lists, scope=scope, surface_name=surface_name}
    local old = player.gui.screen[CONFIRM_FRAME]
    if old and old.valid then old.destroy() end
    local dialog = player.gui.screen.add{type="frame", name=CONFIRM_FRAME, direction="vertical", caption="Large circuit audit scan"}
    dialog.auto_center = true
    local target = scope == "all surfaces" and "across all surfaces" or ("on " .. surface_name)
    dialog.add{type="label", caption=("This scan will examine %s entities %s and may temporarily freeze the game. Continue?"):format(count, target)}
    local buttons = dialog.add{type="flow", direction="horizontal"}
    buttons.add{type="button", name=CONFIRM_CONTINUE, caption="Scan anyway"}
    buttons.add{type="button", name=CONFIRM_CANCEL, caption="Cancel"}
    player.opened = dialog
    return
  end
  set_results(player, scan_entity_lists(entity_lists), scope)
  storage.cssa[player.index].scan_surface_name=surface_name
end
local function rescan(player, scope, surface_name)
  if scope=="all" then count_and_scan_surfaces(player, all_surfaces(), "all surfaces", nil); return end
  local surface=scope=="current" and player.surface or (scope=="selected" and surface_name and game.surfaces[surface_name] or nil)
  if not surface or not surface.valid then player.print("Could not find the requested surface to scan."); return end
  count_and_scan_surfaces(player, {surface}, surface.name, surface.name)
end
local function start_area_selection(player)
  local cursor=player.cursor_stack
  if not cursor then player.print("Cannot start area selection from the current controller."); return end
  if cursor.valid_for_read then player.print("Empty your cursor first, then click Scan area again. Your held item was not changed."); return end
  clear_frame(player)
  local ok,err=pcall(function() cursor.set_stack({name=SCAN_TOOL}) end)
  if not ok then player.print("Could not activate the scan-area tool: " .. tostring(err)); return end
  if not cursor.valid_for_read or cursor.name ~= SCAN_TOOL then
    player.print("Could not put the scan-area selection tool on the cursor. Please report this with factorio-current.log.")
    return
  end
  player.print("Scan-area tool active. Drag with the left mouse button to select a rectangle; this only scans entities.")
end
local function selected_area(event)
  if event.item~=SCAN_TOOL then return end
  local player=game.get_player(event.player_index); if not player or not event.surface or not event.surface.valid then return end
  local results=scan_entities(event.surface.find_entities_filtered{area=event.area})
  local lt=event.area.left_top or event.area[1]; local rb=event.area.right_bottom or event.area[2]
  local scope=("%s area (%d, %d) to (%d, %d)"):format(event.surface.name,math.floor(lt.x),math.floor(lt.y),math.ceil(rb.x),math.ceil(rb.y))
  pcall(function() player.clear_cursor() end)
  storage.cssa=storage.cssa or {}; storage.cssa[player.index]=storage.cssa[player.index] or {results={},selected=nil}
  storage.cssa[player.index].scan_surface_name=event.surface.name
  set_results(player,results,scope); open_gui(player)
end
script.on_init(function()
  pending_scan_entities={}
  storage.cssa={}; for _,p in pairs(game.players) do storage.cssa[p.index]={results={},selected=nil}; remove_legacy_button(p) end
end)
script.on_configuration_changed(function()
  pending_scan_entities={}
  storage.cssa=storage.cssa or {}
  for _,p in pairs(game.players) do
    remove_legacy_button(p)
    local old=storage.cssa[p.index] or {}
    -- Findings from earlier versions had repair-oriented fields; discard this
    -- transient cache so the read-only UI never tries to render stale records.
    storage.cssa[p.index]={results={},selected=nil,scan_surface_name=old.scan_surface_name}
  end
end)
script.on_event(defines.events.on_player_created,function(e)
  local p=game.get_player(e.player_index); if not p then return end; remove_legacy_button(p); storage.cssa=storage.cssa or {}; storage.cssa[p.index]=storage.cssa[p.index] or {results={},selected=nil}
end)
script.on_event(defines.events.on_gui_click,function(e)
  local p=game.get_player(e.player_index); if not p then return end; local el=e.element; if not el or not el.valid then return end
  if el.name==CLOSE then clear_frame(p); return end
  if el.name==CONFIRM_CANCEL then
    pending_scan_entities[p.index]=nil
    local dialog=p.gui.screen[CONFIRM_FRAME]; if dialog and dialog.valid then dialog.destroy() end
    p.opened=nil
    return
  end
  if el.name==CONFIRM_CONTINUE then
    local pending=pending_scan_entities[p.index]
    pending_scan_entities[p.index]=nil
    local dialog=p.gui.screen[CONFIRM_FRAME]; if dialog and dialog.valid then dialog.destroy() end
    p.opened=nil
    if pending then
      local state=storage.cssa and storage.cssa[p.index]
      if state then
        set_results(p,scan_entity_lists(pending.entity_lists),pending.scope)
        state.scan_surface_name=pending.surface_name
      end
    else
      -- A save/load may discard the transient pre-count. Fall back to a fresh all-surfaces scan.
      rescan(p,"all")
    end
    return
  end
  local state=storage.cssa and storage.cssa[p.index]; if not state then return end
  if el.name==SCAN_ALL then rescan(p,"all"); return end
  if el.name==SCAN_CURRENT then rescan(p,"current"); return end
  if el.name==SCAN_AREA then start_area_selection(p); return end
  if el.name==SCAN_SELECTED then
    local frame=p.gui.screen[GUI]; local chosen
    if frame and frame.valid then
      local function find_picker(root)
        if root.name==PICKER then return root end
        for _,child in pairs(root.children) do local found=find_picker(child); if found then return found end end
      end
      local picker=find_picker(frame); if picker and picker.valid then chosen=picker.get_item(picker.selected_index) end
    end
    if chosen then rescan(p,"selected",chosen) else p.print("Choose a surface first.") end; return
  end
  if el.name=="cssa_locate" then local f=state.selected and state.results[state.selected]; if f and f.entity and f.entity.valid then p.centered_on=f.entity end; return end
  if el.name:sub(1,#SELECT_PREFIX)==SELECT_PREFIX then
    local i=tonumber(el.name:sub(#SELECT_PREFIX+1))
    local finding=i and state.results[i]
    if finding then
      -- Factorio's on_gui_click event has no double-click count. Detect two
      -- clicks on the same result within 20 ticks (about one third of a second).
      local is_double_click = state.last_list_click_index==i
        and state.last_list_click_tick
        and (game.tick-state.last_list_click_tick)<=20
      state.selected=i
      -- Mark the current row in place so the list's scroll position is preserved.
      local frame=p.gui.screen[GUI]
      local list=frame and frame.valid and frame.body and frame.body.valid and frame.body.split and frame.body.split.valid and frame.body.split.list
      if list and list.valid then
        for _,row in pairs(list.children) do
          if row.valid and row.name:sub(1,#SELECT_PREFIX)==SELECT_PREFIX then
            local row_index=tonumber(row.name:sub(#SELECT_PREFIX+1))
            local row_finding=row_index and state.results[row_index]
            if row_finding then
              local selected = row_index == i
              row.caption=row_finding.name .. "  [" .. row_finding.surface .. "]  (" .. row_finding.x .. ", " .. row_finding.y .. ")"
              row.style.font_color = selected and {r=1, g=0.82, b=0.25} or {r=1, g=1, b=1}
              row.style.font = selected and "default-bold" or "default"
            end
          end
        end
      end
      draw_details(p)
      if is_double_click then
        state.last_list_click_index=nil
        state.last_list_click_tick=nil
        if finding.entity and finding.entity.valid then
          p.centered_on=finding.entity
          -- Match a normal entity click where Factorio permits opening its GUI.
          pcall(function() p.opened=finding.entity end)
        end
      else
        state.last_list_click_index=i
        state.last_list_click_tick=game.tick
      end
    end
  end
end)
script.on_event(defines.events.on_lua_shortcut,function(e)
  if e.prototype_name ~= SHORTCUT then return end
  local p=game.get_player(e.player_index); if p then open_gui(p) end
end)
script.on_event(defines.events.on_player_selected_area,selected_area)
script.on_event(defines.events.on_player_alt_selected_area,selected_area)
script.on_event(defines.events.on_player_removed,function(e) if storage.cssa then storage.cssa[e.player_index]=nil end; pending_scan_entities[e.player_index]=nil end)

script.on_event(defines.events.on_player_joined_game,function(e)
  local p=game.get_player(e.player_index); if p then remove_legacy_button(p) end
end)
