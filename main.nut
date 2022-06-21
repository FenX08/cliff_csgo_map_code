// Code by Richard Chirkin aka UselessMouth -- Project started at the beginning of 2022 for my map called Cliff.
// https://www.twitch.tv/uselessmouth
// https://twitter.com/UselessMouth
// https://www.reddit.com/user/TheUselessMouth
// https://steamcommunity.com/id/uselessmouth/myworkshopfiles
//
// Version: 1.0 -- 25.05.2022

IncludeScript("de_cliff/vs_library/vs_library.nut");
IncludeScript("de_cliff/vs_library/glow.nut");

// Those masks are already in vs_library, but sometimes code will break on map start with something like "don't know what is MASK_SOLID".
// So we will save them manually here.
const MASK_SOLID          = 0x200400b; // For tracing collision on all solid geometry, players are included.
const MASK_NPCWORLDSTATIC = 0x2000b;   // For tracing collision on all solid geometry, players excluded.

const spectator_team          = 1;
const terrorists_team         = 2;
const counter_terrorists_team = 3;

// Global variables. Will reset on new round.
::dt                       <- FrameTime();
::firearms_array           <- [];
::total_pickups_on_map     <- 0;
::what_team_won_the_round  <- 0;  
::round_ended              <- false;
::last_round_of_half_match <- false;
::speaker_activated        <- false;

// Comeback bonus case variables.
::round_difference_to_give_bonus <- 1;
::healthshot_spawner             <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "healthshot_template" });
::breachcharge_spawner           <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "breachcharge_template" });
::cash_spawner                   <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "cash_template" });
::tagrenade_spawner              <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "tagrenade_template" });
::heavyarmor_spawner             <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "heavyarmor_template" });
::bonus_case_t                   <- null;
::bonus_case_ct                  <- null;
::bonus_case_t_center            <- Vector();
::bonus_case_ct_center           <- Vector();
::bonus_case_t_origin            <- Vector();
::bonus_case_ct_origin           <- Vector();
::bonus_case_t_broke             <- false;
::bonus_case_ct_broke            <- false;
::bonus_t_given                  <- false;
::bonus_ct_given                 <- false;
::bonus_glow_disabled            <- false;

// Bomb stuff. It's only one bomb, so I don't want to wrap it into a struct.
//
// @note: About bomb_timer - I didn't find any way to get timer number from anywhere. If server or custom game mode will
// change Valve's bomb timer (like "mp_c4timer" ConVar), my bomb code will become broken.
//
// If you are not me, you have this code, map's vmf and all of it's assets - just compile and pack the map with a number you want,
// change "mp_c4timer" ConVar to the number you changed in "bomb_timer" and it should work ;-)
// -- Richard Chirkin 15.05.2022
::bomb_target_trigger_array           <- [];
::bomb_pickup_number                  <- 0;
::bomb_glow_radius                    <- 512.0;
::bomb_planted_model                  <- null;
::bomb_physics                        <- null;
::bomb_collision_offset               <- Vector(0,0,0);
::bomb_button_last_second             <- null;
::bomb_planted_light                  <- null;
::bomb_planted_light_distance         <- 90.0;
::bomb_planted_light_current_distance <- bomb_planted_light_distance;
::bomb_planted                        <- false;
::bomb_terrorists_allowed_to_win      <- false;
::is_bomb_defused                     <- false;
::bomb_being_carried                  <- false;
::bomb_is_ready_to_change_light       <- false;
::bomb_changed_light                  <- false;
::can_tone_down_bomb_light            <- false;
::ct_pickup_timer_is_needed           <- true;
::bomb_activate_ct_pickup_timer       <- false;
::bomb_pickup_button_guard_timer      <- 0.0;
::button_guard_timer_max              <- 0.2;  // 0.2 seems like a good trade off between button presses for CT.
::bomb_timer                          <- 40.0; // @note: Bomb timer is 40 seconds in every game mode last I checked. -- Richard Chirkin 09.05.2022
::bomb_beep_timer                     <- 0.0;
::bomb_beep_timer_left                <- bomb_timer;
::bomb_next_beep                      <- 0.0;
::currently_lighting_beep             <- false;
::lighting_beep_timer                 <- 0.0;
::bomb_timer_is_over                  <- false;

// I use classes as C like struct.
// @todo: Make entities weakref.
::Player_Data <- class {
    player              = null;
    userid              = 0;
    team                = 0;
    dead                = false;
    last_position       = Vector();
    new_position        = Vector();
    standing            = true;
    just_respawned      = false;
    weapon_type         = 1;     // -1 = Unknown, 0 = Knife, 1 = Pistol, 2 = Submachinegun, 3 = Rifle, 4 = Shotgun, 5 = Sniper rifle, 6 = Machinegun, 7 = C4, 8 = Taser, 9 = Grenade, 11 = Healthshot, 12 = "Something from Danger Zone?", 13 = Breach charge.
    flashlight          = null;
    firearm_after_death = null;
    prop                = null;
    prop_number         = 0;
    holding_distance    = 0.0;
    air_boost           = null;
    is_air_boosted      = false;

    spotlight                   = null;
    flashlight_sound            = null;
    flashlight_angle_correction = false;
}
::player_data_array <- [];

// Flashlight.
::Flashlight <- class {
    entity           = null;
    enabled          = false;
    is_fully_enabled = false;
    hidden           = true;
    brightness       = 17.0;
    max_brightness   = 17.0;
    current_distance = 800.0;
    max_distance     = 800.0;
    current_fov      = 60.0;
    min_fov          = 25.0;
    max_fov          = 60.0;
}
::corrected_player_flashlight_with_c4_on_round_start <- false;

// Air boost.
::air_boost_trigger_array <- [];
::spawned_grenade_array   <- [];

::Air_Boost <- class {
    entity      = null;
    boost_speed = 1300.0;

    start_point      = 0.0;
    last_point       = 0.0;
    new_point        = 0.0;
    max_boost_height = 170.0;

    stuck_ticks     = 0;
    max_stuck_ticks = 4;
}
::air_boost_array <- [];

::Molotov_Illume <- class {
    inferno                  = 0;     // The id of fire entity that spawns after molotov detonation.
    light                    = null;  // @note: We only got 31 light_dynamic for molotovs.
    sprite                   = null;
    occupied                 = false;
    fading                   = false;
    brightness               = 0;
    max_brightness           = 3;     // Brightness is integer, so we will increase and decrease light through distance.
    distance                 = 0.0;
    distance_lerp            = 0.0;
    distance_prior_to_fading = 0.0;
    max_distance             = 420.0;
    sprite_scale             = 0.0;
    sprite_max_scale         = 4.0;
}
::molotov_illume_array <- [];

// @note:   Do not forget to mark all Source entities that you save in your own variables for weak reference (weakref),
//          so that null comparison of saved entities could work correctly, when/if they are deleted in game by Source.

// @speed:  You can save some variables and use them through map lifetime and do not resave them on new round, like firearms array for example.

//
// Parenting a env_projectedtexture (flashlight) to the player weapon_hand_R attachment:
//
// - Create point_template (flashlight_template) with point_spotlight, ambient_generic entities.
// - Add a flag in player data to indicate the light needs direction update.
// - Set this flag if player switches to knife/grenade/c4.
// - Set light direction only if this flag is true.
//
const FLASHLIGHT_ATTACHMENT = "weapon_hand_R";

// This is used to spawn flashlight template.
::flashlight_spawner        <- VS.CreateEntity("env_entity_maker", { EntityTemplate = "flashlight_template" });
::temp_global_player_data   <- null;
::flashlight_max_fov        <- 60.0;
::flashlight_max_distance   <- 800.0;

// This template is used to spawn flashlight entities. Created in Hammer.
// It has the targetname 'flashlight_template', and spawnflag 0 (NO SPAWNFLAGS)
// It should contain the beam_spotlight and ambient_generic entities as templates.
local flashlight_template = Entities.FindByName(null, "flashlight_template");
flashlight_template.ValidateScriptScope();
flashlight_template.GetScriptScope().PreSpawnInstance <- dummy;

VS.ListenToGameEvent("player_spawn", function(event) {
    // We need to do this once for VS.Library, so we can use our player code on bots as well.
    local player = ToExtendedPlayer(VS.GetPlayerByUserid(event.userid));

    if (!player)
        return;
    if (!player.IsBot())
        return;

}, "player_spawn");

VS.ListenToGameEvent("round_announce_last_round_half", function(event) {
    last_round_of_half_match = true;

}, "round_announce_last_round_half");

function Precache() {
    // You can precache models on round restart, you don't need to restart a map for this.
    // PrecacheModel("models/weapons/w_c4_planted.mdl");
    PrecacheModel("models/player/custom_player/legacy/tm_phoenix_heavy.mdl");
    PrecacheModel("models/player/custom_player/legacy/ctm_heavy.mdl");

    PrecacheModel("models/weapons/v_models/arms/phoenix_heavy/v_sleeve_phoenix_heavy.mdl");
    PrecacheModel("models/weapons/v_models/arms/ctm_heavy/v_sleeve_ctm_heavy.mdl");
}

::initialize_preserved_variables <- function() {
    // @note: When teams are switching sides after half time, values of t_score and ct_score variables are switched in round_end event.
    if (!("t_score" in getroottable())) {
        ::t_score <- 0;
    }

    if (!("ct_score" in getroottable())) {
        ::ct_score <- 0;
    }

    // Someone could reset all rounds on server, if that will happen, we need to reset our preserved variables.
    if (ScriptGetRoundsPlayed() == 0) {
        t_score  = 0;
        ct_score = 0;
    }
}

function OnPostSpawn() {
    // @note: Dynamic light (light_dynamic) is limited to 32 visible lights. If you create it on runtime, it will not be visible, this light needs to be compiled by VRAD. So it's not that much dynamic, ha-ha.
    
    // Preserved variables will live until map is changed or server is shot down.
    initialize_preserved_variables();

    // We need this, because some entities do not reset on new round.
    // For example, chicken or light_dynamic.
    // Also, I saw that if you create projected_texture for flashlight and start new round, it could stay on map.
    // todo: Do this in round_prestart event?
    // reset_entities();

    // Save list of firearms to compare them to dropped items after player death.
    save_firearms_list();

    // Cliff is dark map, so we need to manually light the molotov's fire. For this effect we made 31 ligth_dynamic entities and 31 glow sprites in Hammer.
    // We made 31, because light_dynamic limit is 32 and we use one light_dynamic for bomb light.
    // If 32 players will simultaneously throw molotovs, the 32 molotov will not have light. Guess I'm fine with that.
    local molotov_illume = null;
    local fire_light     = null;
    local fire_sprite    = null;
    for (local i = 1; i < 32; ++i) {
        fire_light  = Entities.FindByName(null, "light_molotov_" + i);
        fire_sprite = Entities.FindByName(null, "sprite_molotov_" + i);

        if (!fire_light)
            break;

        molotov_illume        = Molotov_Illume();
        molotov_illume.light  = fire_light.weakref();
        molotov_illume.sprite = fire_sprite.weakref();

        VS.SetKeyValue(molotov_illume.light, "distance", 0.0);
        EntFireByHandle(molotov_illume.sprite, "HideSprite"); // If you set sprite scale to zero, it will be visible anyway - need to hide it.

        molotov_illume_array.push(molotov_illume);
    }
    
    // We need to count how many pickup props are on map spawn to use this to add new props
    // that were created during round.
    // @todo: Maybe you can actually just place prop and button in Hammer without naming them,
    // and name all of the props, parent buttons and assign output to button on round start (ideally once for the map lifetime).
    local pickup;
    while (pickup = Entities.FindByName(pickup, "prop_pickup_*")) {
        total_pickups_on_map += 1;
    }
    
    // C4 bomb physics collision is created through func_physbox brush entity in Hammer.
    // I do this to give planted C4 collision that would drop and react to physics if player ain't holding it anymore,
    // because Valve's planted C4 doesn't have any collision.
    //
    // "Debris - Don't collide with the player or other debris" flag will not work in func_physbox_multiplayer, need to use func_physbox for that.
    // Debris flag will make bomb collision to not collide with CS:S glass and also point_spotlight will go through bomb collision, when player holds the bomb.
    // We want this behavior, because spotlight wouldn't randomly stop on bomb collision and blind the player, but the glass one is unfortunate, sigh, have to live with that.
    //
    // @note: Also, if you do not use debris flag on physbox, players can actually collide and stand on it, unlike any other physics entities in CS:GO,
    // that will push the player when they are colliding.
    // 
    // @todo: If you'll allow to plant more than 1 bomb on map, you need to add more collision brushes with parented func_button that is placed around func_physbox.
    local bomb_physics;
    while (bomb_physics = Entities.FindByName(bomb_physics, "prop_pickup_bomb_*")) {
        if (bomb_physics) {
            VS.SetKeyValue(bomb_physics, "rendermode", 10); // 10 - Do not render collision.
            VS.SetKeyValue(bomb_physics, "disableshadowdepth", 1); // Stops env_cascade_lighting and env_projected_texture from making shadows for this entity.

            // We don't know how many pickups are on map, so we need to use number of pickups that we counted before
            // and assign pickup number to our bomb that will be planted in the future.
            // @todo: If there will be more than 1 bomb, wrap bomb_pickup_number into array.
            bomb_pickup_number = total_pickups_on_map + 1;
            ++total_pickups_on_map;
            
            // We will rename bomb collision to compatible name that can be used with function that allows us to pick up props.
            // @note:   We parented func_button to func_physbox in Hammer, but if we rename func_physbox
            //          targetname on runtime - func_button will still be parented to func_physbox.
            VS.SetName(bomb_physics, "prop_pickup_" + bomb_pickup_number);

            break;
        }
    }

    // Find and safe button to use it on last second of planted bomb.
    bomb_button_last_second = Entities.FindByName(null, "bomb_button_last_second");

    // Save and disable bomb light at round start.
    // @bug: If light was visible in some spot and we moved to another round, the light could still stay there,
    // even if all entities were reset on new round. point_template will not help, because we need to compile dynamic_light in Hammer, so it could lit geometry.
    bomb_planted_light = Entities.FindByName(null, "bomb_light");
    VS.SetKeyValue(bomb_planted_light, "distance", 0.0);

    // Save bomb target triggers to check if planted bomb is inside them.
    local bomb_target_trigger;
    while (bomb_target_trigger = Entities.FindByName(bomb_target_trigger, "bomb_target_trigger_*")) {
        if (bomb_target_trigger) {
            bomb_target_trigger_array.push(bomb_target_trigger);
        }
    }

    // Save air boost triggers to check for CS:GO physics objects (grenades, dropped items).
    local air_boost_trigger;
    while (air_boost_trigger = Entities.FindByName(air_boost_trigger, "air_boost_trigger_*")) {
        if (air_boost_trigger) {
            air_boost_trigger_array.push(air_boost_trigger);
        }
    }

    // Spawn or delete cases, depending on teams score difference.
    bonus_case_t  = Entities.FindByName(null, "bonus_case_t");
    bonus_case_ct = Entities.FindByName(null, "bonus_case_ct");
    bonus_case_t_center  = bonus_case_t.GetCenter();
    bonus_case_ct_center = bonus_case_ct.GetCenter();
    bonus_case_t_origin  = bonus_case_t.GetOrigin();
    bonus_case_ct_origin = bonus_case_ct.GetOrigin();

    // By checking game type, comeback bonus will only work in these game modes: Casual, Competitive, Wingman, Weapons Expert.
    if (ScriptGetGameType() == 0) {
        if (t_score >= ct_score + round_difference_to_give_bonus) {
            // Give bonus case to CT.
            VS.SetKeyValue(bonus_case_ct, "rendermode", 0);
            bonus_case_t.Destroy();
        } else if (ct_score >= t_score + round_difference_to_give_bonus) {
            // Give bonus case to T.
            VS.SetKeyValue(bonus_case_t, "rendermode", 0);
            bonus_case_ct.Destroy();
        } else {
            // Do not give bonus case to anyone.
            bonus_case_t.Destroy();
            bonus_case_ct.Destroy();
        }
    } else {
        bonus_case_t.Destroy();
        bonus_case_ct.Destroy();
    }

    // Chicken is a preserved entity, they will stay on the same place on new round. Need to teleport them away from playable area on every round.
    local chicken_gordon        = Entities.FindByName(null, "chicken_gordon");
    local chicken_freeman       = Entities.FindByName(null, "chicken_freeman");
    local chicken_gordon_spawn  = Entities.FindByName(null, "chicken_gordon_spawn");
    local chicken_freeman_spawn = Entities.FindByName(null, "chicken_freeman_spawn");
    chicken_gordon.SetAbsOrigin(chicken_gordon_spawn.GetOrigin());
    chicken_freeman.SetAbsOrigin(chicken_freeman_spawn.GetOrigin());
    // Need to disable glow, because glow on preserved entities could transition to the next round.
    Glow.Disable(chicken_gordon);
    Glow.Disable(chicken_freeman);
}

function update() {
    // @note: If lerp value is more then 1.0 (can happen with dt related lerp if tickrate is very low), game will crash.
    // Probably happens because of how VS.Library lerps, who knows, guess extrapolations don't work, will clamp all lerps just in case.

    dt = FrameTime(); // Need to update delta time in case if server decides to change it's tickrate.

    check_and_sort_players_on_server();

    // If there is at least one player on server, update all player related code.
    local player_data_array_length = player_data_array.len();

    for (local i = 0; i < player_data_array_length; ++i) {
        local player_data   = player_data_array[i];
        local player        = player_data.player;

        // Check in what team player currently is.
        player_data.team = player.GetTeam();

        // Decide what to do with spectating player.
        if (player_data.team == spectator_team) {
            local flashlight = player_data.flashlight;

            // If spectator doesn't have flashlight, just skip to the next player.
            // Map got released with a bug, where spectators had flashlights. Looked scary and fun for the first time, but got annoying really fast. Cool idea though.
            if (!flashlight)
                continue;

            // If player died, because he switched to spectator, disable his flashlight, even if it was sticked to a weapon, and skip the rest of the logic for this player.
            player_data.firearm_after_death = null;
            flashlight.enabled              = false;
            flashlight.hidden               = true;
            flashlight.is_fully_enabled     = false;
            
            VS.SetKeyValue(flashlight.entity, "brightnessscale", 0.0);
            EntFireByHandle(player_data.spotlight, "LightOff");

            continue;
        }

        // Check if player respawned.
        if (player_data.dead && player.GetHealth() > 0) {
            player_data.dead                = false;
            player_data.just_respawned      = true;
        }
        
        // Check if player is standing or crouching.
        local standing_vector = player.EyePosition().z - player.GetOrigin().z;
        if (standing_vector > 50.085) {
            player_data.standing = true;
        } else {
            player_data.standing = false;
        }

        pickup_prop_update(player_data);
        flashlight_update(player_data);
        check_if_player_is_in_air_boost(player_data);

        if (player_data.is_air_boosted)
            air_boost_player(player_data);

        // @hack: We check for suspicious position in case, if player switched team. Switching events are slow, so we do this check manually every tick.
        // If player switched team, the prop that he was holding would teleport with him to his spectator camera position,
        // the workaround is to check player's position every tick and compare two vectors, if difference is big, player probably teleported due to switching teams.
        //
        // @bug: Doesn't fully help. Sometimes bomb teleports, if we switch to spectator team. Sometimes bomb will teleport outside of the map.
        // Eh, nasty bug.
        //
        // @note: If map will have teleport features, you would need to take teleports into account with this code.
        player_data.last_position = player_data.new_position;
        player_data.new_position  = player.GetOrigin();

        if (VS.VectorsAreEqual(player_data.last_position, player_data.new_position, 320) == false) {
            if (player_data.prop) {
                remove_prop_from_player(player_data, 2);
            }
        }
    }

    if (bomb_planted)
        planted_bomb_update();

    check_grenade_array();
    check_if_grenade_is_in_air_boost_trigger();
    air_boost_grenades();

    molotov_illumination_update();
    comeback_bonus_case_update();

/*
    // @debug: For local server.
    for (local i = 0; i < player_data_array_length; ++i) {
        local player_data   = player_data_array[i];
        local player        = player_data.player;

        if (player.GetUserID() == 2) { // We got local player.
            local player_position = player.GetOrigin();
            
            // CenterPrintAll("Our position = " + player_position);
            // CenterPrintAll("Is player dead = " + player_data.prop);
            // CenterPrintAll("ct_score = " + ct_score + " t_score = " + t_score);
            // CenterPrintAll("dead = " + player_data.dead);
            CenterPrintAll("last = " + player_data.last_position + "\nnew = " + player_data.new_position);
        }
    }
*/

    return 0; // We do this so that update could be called every tick in main_script entity on map.
}

::check_and_sort_players_on_server <- function() {
    // Need to check if player disconnected - clean his struct and delete him from our array and re-sort it.
    local player_data_array_length = player_data_array.len();

    for (local i = 0; i < player_data_array_length; ++i) {
        local player_data = player_data_array[i];

        if (player_data.player.IsValid() == false || !player_data.player) {
            // Need to drop the prop for disconnected player, if he had any.
            if (player_data.prop)
                remove_prop_from_player(player_data, 0);

            player_data_array.remove(i);
            --player_data_array_length;
            --i;
        }
    }

    // Find out if we got newly connected player. Need check every player on server.
    local player = null;

    while (player = Entities.FindByClassname(player, "player")) {
        // @note: Extended player userid is different from the one you get from events. Maybe something to do with vs.library? Maybe now they are exact ids?
        local player_extended   = ToExtendedPlayer(player);
        local player_userid     = player_extended.GetUserID();
        
        local found_player_in_array = false;

        // If there are players in our array, check if found player is already in array. 
        for (local i = 0; i < player_data_array_length; ++i) {
            if (player_userid == player_data_array[i].userid) {
                found_player_in_array = true;

                break;
            }
        }
        
        // If we didn't find our found player in array - add him to our array.
        // @todo: Local player userid is "-1", need to check what will happen with the code if you run it on server.
        if (!found_player_in_array) {
            local player_data   = Player_Data();
            player_data.player  = player_extended;
            player_data.userid  = player_userid;

            player_data_array.push(player_data);
            ++player_data_array_length;
        }
    }
}

::pickup_prop_update <- function(player_data) {
    // @todo: Right now we only parent the bomb, if we will parent other props, need to do extra logic for them in player_team event, so they
    // wouldn't get teleported with player that, for example, switched to spectators.
    local player        = null;
    local prop          = null;
    local prop_number   = 0;

    player      = player_data.player;
    prop        = player_data.prop;
    prop_number = player_data.prop_number;

    if (prop) {
        // @note: We manually remove prop in remove_prop_from_player function, if player has died and if player has suspicious position.
        // If player died, we remove prop from dead player in item_event event by finding a knife. Yeah, a knife, because Source doesn't give info where player has died.
        // If we got new suspicious player position, we also remove the prop, because sus position means that player probably switched teams.
        //
        // If, for some reason, finding a knife or comparing positions didn't help, we could get a bug, where spectator will fly with a prop.
        // So we will double check if dead player really dropped the prop.
        if (player_data.dead) {
            remove_prop_from_player(player_data, 0);
            return;
        }

        // Move the prop. If it's a bomb, move it differently.
        if (prop_number == bomb_pickup_number) {
            // We want the bomb to be inside player's movement cuboid collision, so that noone could place the bomb inside the wall or place it under the ground.
            //
            // @bug: Bomb moves very jittery if ping is high, but if parent it to player for smooth movement, player could disconnect,
            // and bomb will be destroyed, so we don't have a choice, but to live with this, sigh.
            // We could also try to lerp bomb's position.
            local forward_offset = player.EyeForward() * 16.0;
            local right_offset   = player.EyeRight() * -6.0;
            local up_offset      = player.GetUpVector() * -12.0;

            local new_position = player.EyePosition() + forward_offset + right_offset + up_offset;
            prop.SetAbsOrigin(new_position);

            local eye_angles = player.EyeAngles();
            prop.SetAngles(-73.0, eye_angles.y + 45.0, 0.0); // Rotate the bomb to the player.
        } else {
            // Get vector where we place our prop.
            local length_from_player = player_data.holding_distance;
            local position_from_eyes = player.EyePosition() + player.EyeForward() * length_from_player;
            
            // Lerp prop position for smooth transition.
            local lerp_speed = clamp(10.0 * dt, 0.0, 1.0);

            // Some props have origin at the bottom or at some random place.
            // Need to offset them, so that "holding" position from our eyes would always be at prop's center.
            // @note: GetCenter function returns center of object in global space.
            local origin_offset = prop.GetCenter() - prop.GetOrigin();

            local new_prop_position = VS.VectorLerp(prop.GetOrigin(), position_from_eyes - origin_offset, lerp_speed);
            
            // Update prop position.
            prop.SetAbsOrigin(new_prop_position); // @note: https://developer.valvesoftware.com/wiki/GetAbsOrigin()

            // Update prop rotation.
            // @todo: Right now, I don't know how to lerp Source angles consistently Sadge
            local eye_angles = player.EyeAngles();
            prop.SetAngles(0.0, eye_angles.y, eye_angles.z); // Clamp X axis, so that prop wouldn't lean back and forward.
        }
    } else {
        if (prop_number > 0) {
            // Prop is null, but we got some prop data, that means prop became null while we held it. Clear this data.
            player_data.prop_number      = 0;
            player_data.holding_distance = 0.0;
        }
    }
}

::remove_prop_from_player <- function(player_data, flag) {
    // Flags:  0 - just remove the prop.
    //         1 - place it on knife.
    //         2 - we got suspicious position. 
    local player      = player_data.player;
    local prop        = player_data.prop;
    local prop_number = player_data.prop_number;

    // Wake physics of a prop, so that it doesn't stay in air when we let go of it.
    EntFireByHandle(prop, "Wake");

    // Disable glow on the prop. For the bomb, we disable glow on the bomb model, not collision.
    if (prop_number == bomb_pickup_number) { 
        bomb_being_carried = false;
        Glow.Disable(bomb_planted_model);
    } else {
        Glow.Disable(prop);
    }

    // @hack: This is actually funny - we don't know where player has died. Yeah, Source doesn't give us dead player's position.
    // If you try to do GetOrigin of dead player in player_death event, you will get his spectating position after his death.
    // Also, if player switches teams and dies and his camera jumps to another player, we will get camera's position.
    // Sigh.
    // The workaround is to find a knife that player held, because the knife gets removed when player dies.
    // If we got suspicious position, it probably means that player has died and switched to some team.
    if (flag == 1) {
        local eye_position = player.EyePosition();
        local knife        = null;
        local find_radius  = 42.0;
        
        if (knife = Entities.FindByClassnameNearest("weapon_knife*", eye_position, find_radius)) {
            local death_position = knife.GetOrigin();
            prop.SetAbsOrigin(death_position);
        }
    } else if (flag == 2) {
        prop.SetAbsOrigin(player_data.last_position + Vector(0.0, 0.0, 27.0)); // Need to lift prop a little, because player's origin is on ground.
    }

    player_data.prop             = null;
    player_data.prop_number      = 0;
    player_data.holding_distance = 0.0;
}

::flashlight_update <- function(player_data) {
    // @note: If you create ~90 entities of env_projectedtexture on runtime - game will crash. So, if there will be more than 90 players, game will crash :)
    //
    // @todo: Flashlight doesn't light through unbroken glass entity.
    //
    local player           = player_data.player;
    local flashlight       = player_data.flashlight;
    local spotlight        = player_data.spotlight;
    local flashlight_sound = player_data.flashlight_sound;
    local weapon           = player_data.firearm_after_death;

    // If you kill player with flashlight on, flashlight will stick to a weapon; if it's a warmup or deathmatch gamemode and no one touched the weapon with flashlight,
    // player will respawn and flashlight will be recreated.
    if (player_data.just_respawned) {
        player_data.just_respawned = false;
        player_data.firearm_after_death = null;
        weapon = null;

        flashlight.entity.Destroy();
        player_data.flashlight = null;
        flashlight = null;
    }

    // If player doesn't have flashlight, create one and save.
    if (!flashlight) {
        // If we got here and player is dead, that means, he switched from spectator team to another team.
        // In this case, player will try to create flashligh for himself - don't allow that, just check if player is dead with native function and quit.
        // @note: In main code we check player death with game event, if we will check player health and declare that his dead every frame, flashlight will not stick to player's
        // weapon on his death, that's why we are only checking health here.
        if (player.GetHealth() <= 0)
            return;

        // This player is requesting a flashlight.
        temp_global_player_data = player_data;

        // Spawn entities, and call PostSpawn on the template.
        // This fills the player_data slots.
        flashlight_spawner.SpawnEntity();

        return; // Need to skip flashlight function for one tick for .SpawnEntity() to work, because flashlight creation happens in flashlight_template.GetScriptScope().PostSpawn callback, outside of this flashlight function.
    }

    // If another player picks up dropped weapon of dead player, make weapon null to turn off flashlight completely.
    if (player_data.dead && weapon) {
        if (weapon.GetMoveParent()) {
            weapon = null;
            player_data.firearm_after_death = null;
        }
    }

    // If player is dead and we don't have dropped weapon to stick flashlight to, then turn off flashlight completely.
    if (player_data.dead && !weapon) {
        flashlight.enabled          = false;
        flashlight.hidden           = true;
        flashlight.is_fully_enabled = false;
        
        VS.SetKeyValue(flashlight.entity, "brightnessscale", 0.0);
        EntFireByHandle(spotlight, "LightOff");

        return;
    }

    // We place flashlight at different position depending on if player alive or not.
    // If not, we place flashlight at primary weapon that player dropped on death, but only if he died with flashlight on (we do this check in item_remove event).
    local flaslight_position; 
    local current_forward;

    if (!weapon) {
        // Flashlight is parented to a right hand of the player, but for the forward vector we will use player eyes.
        flaslight_position = flashlight.entity.GetOrigin();
        current_forward    = player.EyeForward();
    } else {
        // We place flashlight sowhere at the center of a barrel. Dropped weapon don't have muzzle_flash attachment.
        local barrel_bone       = weapon.LookupAttachment("weapon_holster_center");
        local barrel_position   = weapon.GetAttachmentOrigin(barrel_bone);
        local weapon_forward    = weapon.GetForwardVector();

        flaslight_position  = barrel_position;
        current_forward     = weapon_forward;
    }

    // Smooth transition between enabled and disabled flashlight.
    // @bug: Here we will manually update sound position, even if it's parented to a flashlight, because of the ambient_generic bug, where, if you play parented sound,
    // sound will stay on the same place where it was played, not moving with parent while playing. Manually moving it helps to fight the bug.
    local light_transition_speed = clamp(20 * dt, 0.0, 1.0);
    if (flashlight.enabled) {
        // If this is the first time we enable flashlight, teleport it to player.
        if (flashlight.hidden) {            
            EntFireByHandle(spotlight, "LightOn");
            flashlight.hidden = false;
        }

        // If flashlight isn't fully lit, keep adding brightness until it's fully enabled.
        if (!flashlight.is_fully_enabled) {
            flashlight.brightness = VS.Lerp(flashlight.brightness, flashlight.max_brightness, light_transition_speed);

            if (VS.CloseEnough(flashlight.brightness, flashlight.max_brightness, 0.01)) {
                flashlight.is_fully_enabled = true;
                flashlight.brightness       = flashlight.max_brightness;
            }
            
            flashlight_sound.SetAbsOrigin(flaslight_position);
            VS.SetKeyValue(flashlight.entity, "brightnessscale", flashlight.brightness);
        }
    } else { // If we turned off flashlight, keep decreasing brightness and also immediately disable spotlight.
        if (!flashlight.hidden) {
            flashlight.is_fully_enabled = false;
            EntFireByHandle(spotlight, "LightOff");

            flashlight.brightness = VS.Lerp(flashlight.brightness, 0.0, light_transition_speed);

            // If we are near zero, clamp to zero and stop updating position.
            if (VS.CloseEnough(flashlight.brightness, 0.0, 0.01)) {
                flashlight.brightness       = 0.0;
                flashlight.hidden           = true;
            }

            flashlight_sound.SetAbsOrigin(flaslight_position);
            VS.SetKeyValue(flashlight.entity, "brightnessscale", flashlight.brightness);
        }
    }

    // Update flashlight position.
    if (!flashlight.hidden) {
        // @bug: Most of the times, spotlight effect can be seen through smoke. We could dynamically check, if there is any active smoke grenades,
        // make custom sphere or box and check if spotlight is inside our custom trigger. But we need to allow to enable spotlight,
        // before smoke completely dissolves, because at the end the smoke is not that thick - need to know smoke timings to be able to do that.

        // Change colors on flashlight creation depending in what team player is.
        if (player_data.team == terrorists_team) {
            VS.SetKeyValue(flashlight.entity, "lightcolor", "240 155 85 300");
            VS.SetKeyValue(spotlight, "rendercolor", "244 181 128");
        } else if (player_data.team == counter_terrorists_team) {
            VS.SetKeyValue(flashlight.entity, "lightcolor", "211 247 254 300");
            VS.SetKeyValue(spotlight, "rendercolor", "211 247 254");
        }

        // beam_spotlight HDR scale was 26.0 - to make the same hdr effect on point_spotlight it needs to be somewhere around 1.5.
        // VS.SetKeyValue(spotlight, "HDRColorScale", 1.5);

        // Trace line to know in what direction we are looking and what we are hitting (other players included with MASK_SOLID).
        local trace;
        if (!weapon) {
            trace = VS.TraceDir(flaslight_position, current_forward, MAX_TRACE_LENGTH, player.self, MASK_SOLID)
        } else {
            // If we stick flashlight to a weapon, we need to ignore his collision.
            // I can only hope that dropped weapon's physics collision is good enough to not get through solid geometry.
            trace = VS.TraceDir(flaslight_position, current_forward, MAX_TRACE_LENGTH, weapon, MASK_SOLID)
        }

        local trace_length  = trace.GetDist();
        
        // Clamp flashlight distance.
        if (trace_length > flashlight.max_distance)
            trace_length = flashlight.max_distance;

        // Need to offset light a little. If we hit player, make different light offset.
        // @todo: Do we want to ignore pickups that we are holding for flashlight, so that light wouldn't stop on pickup prop?
        local trace_length_offset;
        local player_hit;
        local find_player;
        
        if (!weapon) {
            while (find_player = trace.GetEntByClassname("player", player.GetBoundingMaxs().z)) {
                if (find_player.entindex() != player.entindex()) {
                    player_hit = find_player;
                    break;
                } else if (find_player.entindex() == player.entindex()) {
                    // We found ourselves, guess we are too close to surface, and search radius
                    // is big enough to get us. Need to break manually or we will get stuck in an infinite loop.
                    break;
                }
            }
        } else {
            while (find_player = trace.GetEntByClassname("player", player.GetBoundingMaxs().z)) {
                player_hit = find_player;
                break;
            }
        }

        // @hack: Projected texture doesn't have shadows, so we need to manually collide with solid geometry and offset light, 
        // otherwise projected texture will go through geometry and light up everything it goes through.
        // Those calculations will be good enough for this.
        // 
        // In some cases light will go through walls when we are far away from a wall we hitting by trace.
        // I'm doing this, so that projected texture wouldn't just stop on wall, not lighting any objects that are slightly behind it.
        // My only hope, is that this effect will look acceptable in most cases and wouldn't distract that much.
        if (!player_hit) {
            trace_length_offset = trace_length + (trace_length / 2.0);
        } else {
            trace_length_offset = trace_length * 2.0;
        }

        // Lerp flashlight distance for smooth transition.
        local change_distance_speed = clamp(10 * dt, 0.0, 1.0);
        flashlight.current_distance = VS.Lerp(flashlight.current_distance, trace_length_offset, change_distance_speed);

        // Clamp flashlight distance again after manual offset.
        if (flashlight.current_distance > flashlight.max_distance)
            flashlight.current_distance = flashlight.max_distance;
        
        // Set new distance for flashlight.
        VS.SetKeyValue(flashlight.entity, "FarZ", flashlight.current_distance);
        
        // @hack: Max trace length will be 0% of fov. The more the distance the less the fov.
        // This is actually not how light from flashlight works depending on distance from surface (the more the distance the more the fov),
        // but I do this so that projected texture (flashlight) wouldn't get through walls, cause our flashlight
        // is working without casting shadows to not conflict with CS:GO limitations (only one casting shadow projected texture allowed).
        // -- Richard Chirkin 20.02.2022
        local measure_unit      = trace_length_offset / flashlight.max_distance;
        local new_fov           = flashlight.max_fov * (1.0 - measure_unit); // If you don't substract unit from 1, max trace length will be 100% of fov.
        local change_fov_speed  = clamp(10 * dt, 0.0, 1.0);
        
        new_fov = VS.Lerp(flashlight.current_fov, new_fov, change_fov_speed);

        if (new_fov < flashlight.min_fov)
            new_fov = flashlight.min_fov;
            
        flashlight.current_fov = new_fov;
        VS.SetKeyValue(flashlight.entity, "lightfov", new_fov);

        // Flashlight collision detection on solid geometry.
        // @note: When you are near collision distance and fov of spotlight change automatically by Source.
        if (!weapon) {
            // I want to offset projected_texture and spotlight for solid geometry (excluding player collision), because sometimes it could go through thin geometry.
            local spotlight_trace_offset;

            if (!player_hit) {
                // @bug: With net_fakelag (ping simulation on local server) spotlight goes through geometry for a moment, if you bumped the wall while running.
                // Need to set offset to something like 25-32 for bug to disappear, but this effect will look unnatural.
                // I'll leave this bug alone.
                spotlight_trace_offset = spotlight.GetForwardVector() * 8.0;
            } else {
                spotlight_trace_offset = Vector(0,0,0);
            }
            
            local trace_eyes_to_spotlight = VS.TraceLine(player.EyePosition(), spotlight.GetOrigin() + spotlight_trace_offset, player.self, MASK_SOLID);
        
            // Disable (hide) flashlight, if hands got into solid geometry.
            if (trace_eyes_to_spotlight.DidHit()) {
                VS.SetKeyValue(flashlight.entity, "brightnessscale", 0.0);
                EntFireByHandle(spotlight, "LightOff");
            } else {
                if (flashlight.is_fully_enabled) {
                    VS.SetKeyValue(flashlight.entity, "brightnessscale", flashlight.brightness);
                    EntFireByHandle(spotlight, "LightOn");
                }
            }
        }

        if (player_data.flashlight_angle_correction) {
            // @hack: Transform player eye direction to the flashlight's parent (attachment) space,
            // then set the flashlight direction to player eye direction.
            //
            // Need to do local and global rotation vectors conversion, because of the parenting.
            // GetForwardVector() returns the vector in world space,
            // SetForwardVector() sets in local space.
            // @bug: It looks jerky, probably because of the world model animation on knife, grenades, etc.
            local world_to_attachment = matrix3x4_t();
            local attachment = player.LookupAttachment(FLASHLIGHT_ATTACHMENT);
            VS.AngleIMatrix(player.GetAttachmentAngles(attachment), null, world_to_attachment);

            local target_forward = player.EyeForward();
            VS.VectorRotate(target_forward, world_to_attachment, target_forward);

            local current_forward = flashlight.entity.GetForwardVector();
            VS.VectorRotate(current_forward, world_to_attachment, current_forward);

            // Approach the target slowly to smooth out jerky movement
            local correction_lerp_speed = clamp(12.8 * dt, 0.0, 1.0);
            local approach = VS.VectorLerp(current_forward, target_forward, correction_lerp_speed);
            flashlight.entity.SetForwardVector(approach);
        }

        // If player is dead and we got a weapon, manually place flashlight in weapon, without using parenting.
        if (weapon) {
            flashlight.entity.SetAbsOrigin(flaslight_position);
            flashlight.entity.SetForwardVector(current_forward);
        }
    }
}

// This is called when entities are spawned.
flashlight_template.GetScriptScope().PostSpawn <- function(entities) {
    local spotlight, sound_ent;
 
    // 'entities' contains the entities this template spawns
    foreach (name, ent in entities)
    {
        switch (ent.GetClassname())
        {   
            // Beam spotlight, despite the fact that it's a client-side entity, works very good when it is spawned with template - it doesn't
            // stuck in geometry, it dynamically changes colors and so on. If it was created and compiled in Hammer, it will work wonky.
            // Also, beam_spotlight updates rotations smoothly, but point_spotlight rotation is laggy, I guess for some legacy reasons.
            case "beam_spotlight":
                spotlight = ent;
                break;
            case "ambient_generic":
                sound_ent = ent;
                break;
        }
    }
    
    // @bug: env_projectedtexture works wonky with displacements - some effects on material will not show up while lit with projected texture,
    // and also works wonky with models that are placed into the water and are seen to the player - if you lit them, they will turn black under projected texture.
    local flashlight = VS.CreateEntity("env_projectedtexture", {
        lightcolor      = "255 255 255 255",
        // enableshadows   = 0,                     // Only 1 projected texture with shadows can be on a map in CS:GO. Disabled by default.
        brightnessscale = 0,                        // Light should not be visible on creation.
        lightfov        = flashlight_max_fov,
        nearz           = 0.1,
        farz            = flashlight_max_distance,
        spawnflags      = 3                         // +1 = Enabled, +2 = Always update (moving light).
    });
 
    // Align children to the parent.
    spotlight.SetAbsOrigin(flashlight.GetOrigin());
    sound_ent.SetAbsOrigin(flashlight.GetOrigin());
    spotlight.SetAngles(0,0,0);
    flashlight.SetAngles(0,0,0);
 
    // Parent all templated entities to env_projectedtexture so that we only have to manage one entity.
    VS.SetParent(spotlight, flashlight);
    VS.SetParent(sound_ent, flashlight);
 
    local player_data = temp_global_player_data; // This is the player that requested these entities.
    temp_global_player_data = null; // Clear the temporary global variable.
 
    player_data.flashlight        = Flashlight();
    player_data.flashlight.entity = flashlight.weakref();
    player_data.flashlight_sound  = sound_ent.weakref();
    player_data.spotlight         = spotlight.weakref();
 
    // Parent env_projectedtexture to player right hand.
    VS.SetParent(player_data.flashlight.entity, player_data.player.self);
    EntFireByHandle(player_data.flashlight.entity, "SetParentAttachment", FLASHLIGHT_ATTACHMENT);

    // To be able to move flashlight, we need to do this once for projected_texture, even if it was created with a flag "Always update",
    // or it will randomly stuck and will not move.
    EntFireByHandle(player_data.flashlight.entity, "AlwaysUpdateOn");

    player_data.flashlight.enabled = true; // I enable flashlights by default.

    // We don't know with what weapon player spawns on new round, but we always know, that if player has bomb on round start, he will hold
    // the bomb in his hands. We need to find this player and correct his flashlight just for him.
    if (!corrected_player_flashlight_with_c4_on_round_start) {
        local player = player_data.player;
        if (player) {
            if (player_data.team == terrorists_team) {
                // C4 always comes second in player hierarchy on round start.
                local c4 = player.FirstMoveChild().NextMovePeer();

                if (c4.GetClassname() == "weapon_c4") {
                    corrected_player_flashlight_with_c4_on_round_start = true;
                    player_data.flashlight_angle_correction = true;
                    player_data.weapon_type = 7;
                }
            }
        }
    }

}

::check_if_player_is_in_air_boost <- function(player_data) {
    // We want to manually check player in the trigger, because entity trigger works wonky, sometimes they will output nothing, if more than 1 player are touching it.
    if (!player_data.is_air_boosted) {
        local trigger_array_size = air_boost_trigger_array.len();

        if (trigger_array_size > 0) {
            local player = player_data.player;
            local player_position = player.GetOrigin();
            local start_player    = player_position + player.GetBoundingMins();
            local end_player      = player_position + player.GetBoundingMaxs();
    
            for (local i = 0; i < trigger_array_size; ++i) {
                local trigger = air_boost_trigger_array[i];
                local trigger_position = trigger.GetOrigin();
    
                // Get global vectors of mins and maxs of trigger collision. 
                local start = trigger_position + trigger.GetBoundingMins();
                local end   = trigger_position + trigger.GetBoundingMaxs();
    
                // If player is in air boost trigger, add him to air boost logic.
                if (VS.IsBoxIntersectingBox(start, end, start_player, end_player)) {
                    player_data.is_air_boosted = true;

                    player_data.air_boost = Air_Boost();
                    player_data.air_boost.start_point = player_position.z;

                    break;
                }
            }
        }
    }
}

::air_boost_player <- function(player_data) {
    // @bug: Velocity of height does not change if player didn't jump prior entering the air boost trigger or if he didn't fall into trigger.
    // Velocity will take effect only if you teleport player 20 units high from grounded position.
    // If you do that, 2 boosted players could stuck in each other.
    // Sometimes you can jump in the trigger and still land on the platform without being air boosted.

    // @note: Player's ragdoll bodies work client side - can not be air boosted.
    // Maybe you could make "trigger_serverragdoll" and use it with "phys_ragdollmagnet" with a negative magnetic force, but we don't
    // want this kind of calculations on server. Think this could work on singleplayer maps though.

    // If player is dead, clear and return.
    if (player_data.dead) {
        player_data.is_air_boosted = false;
        player_data.air_boost = null;
        
        return;
    }

    local air_boost = player_data.air_boost;

    local start_point     = air_boost.start_point;
    local last_point      = air_boost.last_point;
    local new_point       = air_boost.new_point;
    local stuck_ticks     = air_boost.stuck_ticks;
    local max_stuck_ticks = air_boost.max_stuck_ticks;

    // Check if we stuck, if Z position did not change in certain amount of ticks - we probably hit something.
    local player_probably_stuck = false;
    local player_stuck = false;

    if (VS.CloseEnough(new_point, last_point, 0.250)) {
        player_probably_stuck = true;
    }

    if (player_probably_stuck) {
        air_boost.stuck_ticks = stuck_ticks + 1;
    } else {
        air_boost.stuck_ticks = 0;
    }

    if (stuck_ticks >= max_stuck_ticks) {
        player_stuck = true;
    }

    // If player didn't stuck mid air and didn't reach max height, continue boosting player.
    if (!player_stuck && new_point - start_point < air_boost.max_boost_height) {
        local player = player_data.player;
        local boost_speed = air_boost.boost_speed;
        local velocity    = player.GetVelocity();
    
        // Change only height velocity.
        local lerp_strength = 0.0;
    
        if (velocity.z < -130.0) {
            lerp_strength = (velocity.z / 100.0) * -1.0; // If we are falling, add extra speed.
        } else {
            lerp_strength = 1.3;
        }
    
        lerp_strength = clamp(lerp_strength * dt, 0.0, 1.0);
    
        local new_height = VS.Lerp(velocity.z, boost_speed, lerp_strength);
    
        velocity = Vector(velocity.x, velocity.y, new_height);
        player.SetVelocity(velocity);
        
        local new_point = player.GetOrigin().z;
    
        air_boost.last_point = air_boost.new_point; // Need to save last point to check if player stuck mid air.
        air_boost.new_point  = new_point;
    } else {
        // Air boost for the player is finished.
        player_data.is_air_boosted = false;
        player_data.air_boost = null;
    }
}

::planted_bomb_update <- function() {
    // Move bomb model with collision.
    //
    // @bug: If we parent planted c4 to bomb collision instead of moving it in code (like we do), the bomb will always display at 0,0,0 coordinates on the radar for ct and terrorist team.
    // When we are holding (pick up mode) planted bomb, collision moves faster than the model, parenting the model to collision could fix this, but will break the radar thing and also,
    // if you parent bomb to player, could happen nasty things, like, if player, that was holding a bomb, disconnected, resulting in bomb entity deletion, that will break everything.
    //
    // @bug: Collision can lay sideways on the ground, but models are not, leading to visual bug where model is above ground.
    // If you just copy angles from collision, models could get underground. Meh.
    bomb_planted_model.SetAbsOrigin(bomb_physics.GetOrigin() - bomb_collision_offset);
    bomb_planted_model.SetForwardVector(bomb_physics.GetForwardVector());

    if (!is_bomb_defused) {
        // @hack @bomb_pick_up_for_ct: Need to increase timings between pressing the bomb to pick it up for CT players. Because our pickup button can conflict with
        // defusing button. Depending on the angle CT is looking at the bomb, he will trigger either defuse button or our button.
        // We need to give an option to pick up the bomb through defusing, because defusing button will not let us trigger our pick up button.
        //
        // Sometimes CT can trigger defuse button with our button simultaneously, this will result in undesired effect that player
        // picks up the bomb and immediately puts it back on the ground - we don't want that, that's why we will use timer check.
        if (bomb_activate_ct_pickup_timer) {
            if (bomb_pickup_button_guard_timer < button_guard_timer_max) {
                bomb_pickup_button_guard_timer += dt;
            } else {
                bomb_pickup_button_guard_timer  = 0.0;
                bomb_activate_ct_pickup_timer   = false;
            }
        }

        // We want to update our beeping dynamic light with red particle light on planted bomb, so it would be visible in dark environments.
        if (bomb_beep_timer <= bomb_timer && !bomb_changed_light) {
            // Time length of visible beeping light.
            // @note:   When dynamic light switches off with zero distance, light stays on models for some little time.
            //          Need to adjust this manually and in the future maybe lerp brightness values for the light.
            local beep_length = 0.1;

            // Time between plant and first beep is 1 second, but it needs to be lower for some reason.
            // Maybe delay caused by bomb event? I don't know.
            local time_before_start = 0.90;

            // Update timer to know when we need to switch off our light.
            if (currently_lighting_beep) {
                lighting_beep_timer += dt;

                if (lighting_beep_timer >= beep_length) {
                    currently_lighting_beep = false;
                    lighting_beep_timer     = 0.0;
                    VS.SetKeyValue(bomb_planted_light, "distance", 0.0);
                }
            }

            // @note: As time passes, the radius of red particle on bomb increases.
            // We would do this too with our dynamic light, but I think it's radius can not be changed after map compile.

            // Calculate next beep. We start to show the light after 1 second.
            if (bomb_beep_timer >= bomb_next_beep && bomb_beep_timer >= time_before_start) {
                // We can now show light.
                // @todo: We can change dynamic light distance with smooth lerp.
                currently_lighting_beep = true;                    
                VS.SetKeyValue(bomb_planted_light, "distance", bomb_planted_light_distance);
                
                // Formula is from: https://www.reddit.com/r/GlobalOffensive/comments/iguyc7/if_anyone_has_ever_wondered_what_the_formula_for/
                local period_to_next_beep = 0.1 + 0.9 * (bomb_beep_timer_left / bomb_timer);

                // Determine when the next beep will happen.
                bomb_next_beep = bomb_beep_timer + period_to_next_beep;
            }
            
            bomb_beep_timer_left    -= dt;
            bomb_beep_timer         += dt;
        }

        check_if_bomb_is_in_bomb_target_trigger();
    }

    // Need to tone down bomb light on the last second until explosion.
    // @note: If we defuse the bomb after light change, light will also dim.
    if (can_tone_down_bomb_light) {
        bomb_planted_light_current_distance -= bomb_planted_light_distance / (1.0/dt); // Tone down bomb light to zero in one second.
        VS.SetKeyValue(bomb_planted_light, "distance", bomb_planted_light_current_distance);

        // Clear stuff, if bomb was defused after light change.
        if (bomb_timer_is_over) {
            bomb_is_ready_to_change_light   = false;
            bomb_changed_light              = false;
            can_tone_down_bomb_light        = false;

            if (bomb_planted_light)
                bomb_planted_light.Destroy(); // If bomb was defused in the last second, we will wait for light to dim and kill it.
        }
    }
}

VS.ListenToGameEvent("inspect_weapon", function(event) {
    // Flashlight enables through pressing "inspect weapon" button (default button is "F").
    local player                    = VS.GetPlayerByUserid(event.userid);
    local player_data_array_length  = player_data_array.len();
    local player_data               = null;

    if (!player) {
        return;
    }

    for (local i = 0; i < player_data_array_length; ++i) {
        player_data = player_data_array[i];

        if (!player_data.player)
            continue;

        if (player_data.player.entindex() == player.entindex()) {
            EntFireByHandle(player_data.flashlight_sound, "PlaySound"); // We will play the same sound on OFF and ON states of the flashlight.

            if (player_data.flashlight.enabled) {
                player_data.flashlight.enabled = false;
            } else {
                player_data.flashlight.enabled = true;
            }
            
            break;
        }
    }

}, "inspect_weapon");

VS.ListenToGameEvent("item_equip", function(event) {
    // What currently player holds in his hands (item, weapon).
    // @note: This information is saved only when player switches weapons or picks a new one, this event doesn't work on player spawn.
    // At the round start, we will always assume that player holds the pistol.
    local player                    = VS.GetPlayerByUserid(event.userid);
    local player_data_array_length  = player_data_array.len();
    local player_data               = null;
    local weapon_type               = event.weptype;

    if (!player) {
        return;
    }

    for (local i = 0; i < player_data_array_length; ++i) {
        player_data = player_data_array[i];

        if (!player_data.player)
            continue;

        if (player_data.player.entindex() == player.entindex()) {
            player_data.weapon_type = weapon_type;

            // Mark angle correction for this player if the item is a knife, grenade, C4, healthshot or breach charge.
            // This makes the flashlight always directed at where the player is looking at, however
            // the flashlight is slightly jittery while the player is standing still (but not while moving).
            if (weapon_type == 0 || weapon_type == 9 || weapon_type == 7 || weapon_type == 11 || weapon_type == 13) {
                player_data.flashlight_angle_correction = true;
            } else {
                player_data.flashlight_angle_correction = false;
         
                // Re-orient looking slightly towards where the player is aiming at (up and left)
                if (player_data.flashlight.entity)
                    player_data.flashlight.entity.SetForwardVector(Vector(0.9997, 0.005, 0.024));
            }

            break;
        }
    }

}, "item_equip");

VS.ListenToGameEvent("item_remove", function(event) {
    // If player dies, weapons get removed through this event.
    local player = VS.GetPlayerByUserid(event.userid);

    // If player disconnected (or bot was kicked), he will trigger this event, leave items on a map, but the player will be null.
    if (!player) {
        return;
    }

    // If player died with flashlight on, we need to decide: do we need to stick flashlight to firearm, if he dropped any.
    local player_data_array_length = player_data_array.len();
    local player_data              = null;

    for (local i = 0; i < player_data_array_length; ++i) {
        player_data = player_data_array[i];

        if (!player_data.player)
            continue;

        if (player_data.player.entindex() == player.entindex()) {
            if (player.GetHealth() <= 0) {
                // Need to set prop's position to player death position, because, before player death, prop position could be somewhere in solid geometry.
                if (player_data.prop)
                    remove_prop_from_player(player_data, 1);

                // If we already saved first primary weapon, break.
                if (player_data.firearm_after_death)
                    break;

                if (player_data.flashlight.enabled) {
                    local firearms_array_length = firearms_array.len();

                    for (local j = 0; j < firearms_array_length; ++j) {
                        if (event.item == firearms_array[j]) {
                            // Dropped weapons spawns from player's eyes.
                            // @bug: Flashlight will not stick to a weapon, if player died by switching teams, because his eye position will be somewhere far from his dead body.
                            local eye_position  = player.EyePosition();
                            local weapon        = null;
                            local find_radius   = 42.0;

                            // Find what kind of weapon we just dropped.
                            if (weapon = Entities.FindByClassnameNearest("weapon_" + event.item, eye_position, find_radius)) {
                                player_data.firearm_after_death = weapon;
                                player_data.flashlight_angle_correction = false;

                                // Need to unparent flashlight from the player.
                                // For the weapon we will just update flashlight position, forgeting about server prediction.
                                VS.SetParent(player_data.flashlight.entity, null);
                                
                                break;
                            }
                        }
                    }
                }
            }

            break;
        }
    }

}, "item_dropped");

VS.ListenToGameEvent("player_death", function(event) {
    // Need to know when player died.
    local player                    = VS.GetPlayerByUserid(event.userid);
    local player_data_array_length  = player_data_array.len();
    local player_data               = null;

    if (!player) {
        return;
    }

    for (local i = 0; i < player_data_array_length; ++i) {
        player_data = player_data_array[i];

        if (!player_data.player)
            continue;

        if (player_data.player.entindex() == player.entindex()) {
            player_data.dead = true;
        }
    }

}, "player_death");

VS.ListenToGameEvent("bot_takeover", function(event) {
    // Need to disable bot's flashlight, if player got control of the bot.
    local bot                       = VS.GetPlayerByUserid(event.botid);
    local player_data_array_length  = player_data_array.len();
    local player_data               = null;

    for (local i = 0; i < player_data_array_length; ++i) {
        player_data = player_data_array[i];

        if (!player_data.player)
            continue;

        if (player_data.player.entindex() == bot.entindex()) {
            player_data.firearm_after_death         = null;
            player_data.flashlight.enabled          = false;
            player_data.flashlight.hidden           = true;
            player_data.flashlight.is_fully_enabled = false;
            
            VS.SetKeyValue(player_data.flashlight.entity, "brightnessscale", 0.0);
            EntFireByHandle(player_data.spotlight, "LightOff");

            break;
        }
    }

}, "bot_takeover");

::pick_up_prop <- function(player, prop_number) {
    // Someone pressed a button that is associated with pickup prop.
    //
    // We use button brush entity, because +Use output on models will always return the first player on a server, unlike buttons.
    // That means +Use output on models works only for singleplayer stuff.
    
    // @todo:   Document on what you need to do in Hammer to get this working.
    // @todo:   Maybe you can create buttons dynamically on Map Start by setting
    //          their bounding box with SetSize and writing proper outputs in them?

    // Firstly, we need find player and check if received prop is already held by someone.
    local prop = Entities.FindByName(null, "prop_pickup_" + prop_number);

    local player_index_that_wants_to_pick_up        = 0;
    local player_index_that_already_holds_the_prop  = -1;

    local player_data_array_length  = player_data_array.len();

    for (local i = 0; i < player_data_array_length; ++i) {
        if (!player_data_array[i].player)
            continue;

        if (player_data_array[i].player.entindex() == player.entindex()) {
            player_index_that_wants_to_pick_up = i;
        }

        if (player_data_array[i].prop && player_data_array[i].prop.entindex() == prop.entindex()) {
            player_index_that_already_holds_the_prop = i;
        }
    }

    local j = player_index_that_wants_to_pick_up;
    local k = player_index_that_already_holds_the_prop;

    if (k == -1) { // No one is holding received prop, that means player wants to pick it up.
        if (player_data_array[j].prop) {
            return; // If player already has prop in his hands, don't allow to pick up received one.
        }

        player_data_array[j].prop           = prop.weakref();
        player_data_array[j].prop_number    = prop_number;

        // Calculate maximum length of bounding box to know how far should I extent prop from eyes.
        // After picking up, prop angles a straight forward from player view, so we only use it's X axis for bounding length.
        // @todo: You can try to slow down players if object bounding box is too big, like, if it's big, maybe it's mass is big too.
        local bounding_length = prop.GetBoundingMaxs().x;

        // Player eyes are coming from center of a box.
        // We will multiply it by four, so that prop will always be one and a half player away from end of player's bounding box. 
        local player_bounding_length    = player.GetBoundingMaxs().x * 4;
        local length_from_player        = bounding_length + player_bounding_length;
        
        player_data_array[j].holding_distance = length_from_player;

        // Specify glow radius. Be aware, that everyone will see the glow in that specified radius.
        local glow_radius = length_from_player * 7; // @note: If you multiply less, glow will be dimmer (for holding player) if you'll look straight up for example.

        // Check if our prop is a bomb, if not, just set the glow to the general prop.
        if (prop_number == bomb_pickup_number) {
            bomb_being_carried = true;
            bomb_glow_radius = glow_radius;
            
            if (is_bomb_defused) {
                Glow.Set(bomb_planted_model, "81 215 47", 2, glow_radius); // Set it to green color when bomb is defused, because it's the color of defused bomb on the radar.
            } else if (bomb_changed_light) {
                Glow.Set(bomb_planted_model, "253 245 159", 2, glow_radius); // White-yellow color at the last ~2 seconds of bomb timer.
            } else {
                Glow.Set(bomb_planted_model, "241 58 58", 2, glow_radius); // Bomb, unlike other props, will have different (reddish) color.
            }
        } else {
            Glow.Set(prop, "255 140 0", 2, glow_radius);
        }

    } else if (j == k) { // Player is holding the same prop we received, that means he wants to let go of it.
        // Wake physics of a prop, so that it doesn't stay in air when we let go of it.
        EntFireByHandle(player_data_array[j].prop, "Wake");

        // Disable glow on the prop. For the bomb, we disable glow on the bomb model, not collision.
        if (prop_number == bomb_pickup_number) { 
            bomb_being_carried = false;
            Glow.Disable(bomb_planted_model);
        } else {
            Glow.Disable(prop);
        }

        // Clear prop data for the player.
        player_data_array[j].prop               = null;
        player_data_array[j].prop_number        = 0;
        player_data_array[j].holding_distance   = 0.0;

    } else if (j != k) { // Someone holds the prop, that player wants to pick up. Give it to him.
        if (player_data_array[j].prop) {
            return; // If player already has prop in his hands, don't allow to pick up a prop from another player.
        }

        player_data_array[j].prop               = player_data_array[k].prop;
        player_data_array[j].prop_number        = player_data_array[k].prop_number;
        player_data_array[j].holding_distance   = player_data_array[k].holding_distance;

        // Clear prop data from player that held the prop.
        player_data_array[k].prop               = null;
        player_data_array[k].prop_number        = 0;
        player_data_array[k].holding_distance   = 0.0;
    }
}

::check_if_bomb_is_in_bomb_target_trigger <- function() {
    local trigger_array_size = bomb_target_trigger_array.len();

    if (trigger_array_size > 0) {
        local bomb_position = bomb_physics.GetOrigin();
        local start_bomb    = bomb_position + bomb_physics.GetBoundingMins();
        local end_bomb      = bomb_position + bomb_physics.GetBoundingMaxs();

        for (local i = 0; i < trigger_array_size; ++i) {
            local trigger = bomb_target_trigger_array[i];
            local trigger_position = trigger.GetOrigin();

            // Get global vectors of mins and maxs of trigger collision. 
            local start = trigger_position + trigger.GetBoundingMins();
            local end   = trigger_position + trigger.GetBoundingMaxs();

            // If bomb is in trigger, then mark that T team are allowed to win after bomb timer end.
            if (VS.IsBoxIntersectingBox(start, end, start_bomb, end_bomb)) {
                bomb_terrorists_allowed_to_win = true;
                break;
            } else {
                bomb_terrorists_allowed_to_win = false;
            }
        }

        // CenterPrintAll("Bomb is in trigger = " + bomb_terrorists_allowed_to_win);
    }
}

VS.ListenToGameEvent("bomb_planted", function(event) {
    // Intialize planted bomb to work as pickup prop.
    // @note: Code only works for 1 bomb scenario - will need additional work, if we will allow to plant more than 1 bomb.
    bomb_planted = true;

    bomb_physics = Entities.FindByName(null, "prop_pickup_" + bomb_pickup_number);

    // Find and save planted bomb.
    bomb_planted_model = Entities.FindByClassname(null, "planted_c4");

    // We need to offset position of collision, because planted c4 origin is at the bottom and collision origin is at center.
    // I will finetune the offset depending on bounding box of collision brush.
    // Collision size: x = 9.586, y = 7.043, z = 3.413.
    local collision_height  = bomb_physics.GetBoundingMaxs().z * 0.5796;
    local forward_offset    = bomb_planted_model.GetForwardVector() * 0.188;
    local left_offset       = bomb_planted_model.GetLeftVector() * -0.21876; // @note: GetLeftVector() is actually right vector.
    local height_offset     = bomb_planted_model.GetUpVector() * collision_height;
    bomb_collision_offset   = forward_offset + left_offset + height_offset;
    local new_position      = bomb_planted_model.GetOrigin() + bomb_collision_offset;

    // Place bomb collision at planted bomb position.
    bomb_physics.SetAbsOrigin(new_position);

    // Copy rotation of planted bomb to bomb collision.
    local bomb_planted_rotation = bomb_planted_model.GetAngles();
    bomb_physics.SetAngles(bomb_planted_rotation.x, bomb_planted_rotation.y, bomb_planted_rotation.z);

    VS.SetKeyValue(bomb_planted_model, "LagCompensate", 1); // Will this even work? How does this help?

    // Wake the physics of the bomb, so it could fall or get air boosted.
    EntFireByHandle(bomb_physics, "Wake");

    // Valve's bomb sprite changes on 39.0 second, but we will change our light around 39.1 second.
    // If you defuse the bomb between 39-41 seconds, light will also change and dim.
    // @note: Even if you change "mp_c4timer" ConVar and bomb_timer number to something that is not 40 seconds - the code will work.
    // @note: VS.Timer is a timer entity, in most cases you need to disable it, because if you not, it will repeat function with the specified interval.
    VS.Timer(0, bomb_timer - 1.0, bomb_light_change_initialize);
    VS.Timer(0, bomb_timer - 0.88, change_our_bomb_light_at_the_end);

    VS.Timer(0, bomb_timer, last_second_logic_of_bomb);

    // The actual explosion happens after one second when timer ends, so we will add 1 second to whole timer.
    // @note: Bomb timer is 40 seconds in every game mode last I checked.
    local explosion_time = bomb_timer + 1.0;

    // We will check if planted bomb is on site. When several ticks left, decide who will win before explosion.
    local ct_win_before_timer_end = explosion_time - (dt * 4);
    VS.Timer(0, ct_win_before_timer_end, check_if_planted_bomb_is_on_site);

    VS.Timer(0, explosion_time, timer_is_over);

}, "intialize_planted_bomb");

::bomb_light_change_initialize <- function() {
    if (!is_bomb_defused) {
        bomb_is_ready_to_change_light = true;
    }
}

::change_our_bomb_light_at_the_end <- function() {
    if (bomb_is_ready_to_change_light) {
        bomb_changed_light = true;

        // Change dynamic color of dynamic light on the bomb.
        VS.SetKeyValue(bomb_planted_light, "_light", "253 245 159");
        VS.SetKeyValue(bomb_planted_light, "distance", bomb_planted_light_distance);
        
        if (bomb_being_carried)
            Glow.Set(bomb_planted_model, "253 245 159", 2, bomb_glow_radius);
    }
}

::last_second_logic_of_bomb <- function() {
    if (!is_bomb_defused) {
        // @hack: Defuse doesn't work on last second before explosion, but defuse button is still placed on a bomb that prevents CT players
        // to use our bomb's pick up button at different angles.
        // To combat this problem, I'm creating and placing big button on a bomb that can be pressed even if you are looking away from it.
        // Sometimes it will not work for CT if they are too close to a bomb, maybe.
        //
        // I could use VS.Library's callback and listen for "use" button presses and checking if this player is looking at the bomb, but
        // callbacks are bugged - they break player's prediction that can be saw by writing "host_timescale 0.1" in the console with enabled callbacks.
        // So I'll use big button for now.
        // -- Richard Chirkin 12.05.2022
        bomb_button_last_second.SetAbsOrigin(bomb_physics.GetOrigin());
        VS.SetParent(bomb_button_last_second, bomb_physics);
        ct_pickup_timer_is_needed = false;
    }

    // On the last second bomb sprite will tone down to zero until explosion, we will do this too with our light.
    // Light dims not only before explosion, but also if we defused the bomb after light change.
    if (bomb_is_ready_to_change_light)
        can_tone_down_bomb_light = true;
}

::press_on_bomb <- function(player) {
    // @hack: We check if CT player is allowed to pick up or put down the bomb to not conflict with defuse button and our pick up button.
    // For details search: @bomb_pick_up_for_ct
    if (ct_pickup_timer_is_needed && player.GetTeam() == counter_terrorists_team) {
        if (bomb_activate_ct_pickup_timer)
            return;

        bomb_activate_ct_pickup_timer = true;
    }

    pick_up_prop(player, bomb_pickup_number);
}

VS.ListenToGameEvent("bomb_begindefuse", function(event) {
    // Pressing the bomb for CT players. Defuse doesn't work on the last second before explosion.
    // CT can not pick up a bomb through begin defuse if they are looking at bomb with not-allowed angles, so we use this method with
    // our own pick up button (press_on_bomb function) simultaneously.
    local player = VS.GetPlayerByUserid(event.userid);
    
    // @hack: We check if CT player is allowed to pick up or put down the bomb to not conflict with defuse button and our pick up button.
    // For details search: @bomb_pick_up_for_ct
    if (bomb_activate_ct_pickup_timer)
        return;

    bomb_activate_ct_pickup_timer = true;

    pick_up_prop(player, bomb_pickup_number);

}, "pick_up_bomb_for_ct");

VS.ListenToGameEvent("bomb_defused", function(event) {
    // If bomb light is not destroyed (on bomb defuse for example), it will stay in the same place on new round, because, I guess, it's a client-side entity.
    // This will not be a problem, we will destroy or turn off the light depending on end round conditions.
    //
    // If server will manually restart the round, light will stay on new round - guess I'll ignore this, because I didn't find any functions
    // that clean stuff before round reset.
    // @todo: Chech logic_auto, maybe there you could clean stuff before new round - https://developer.valvesoftware.com/wiki/Logic_auto
    is_bomb_defused                     = true;
    bomb_terrorists_allowed_to_win      = false;
    ct_pickup_timer_is_needed           = false;

    if (!bomb_is_ready_to_change_light)
        bomb_planted_light.Destroy(); // If bomb light didn't change the color, just kill the light.

    bomb_button_last_second.Destroy(); // We don't need big button on bomb if we defused at the last second before explosion.

    if (bomb_being_carried)
        Glow.Set(bomb_planted_model, "81 215 47", 2, bomb_glow_radius); // Set it to green color when bomb is defused.

}, "bomb_defused");

VS.ListenToGameEvent("bomb_exploded", function(event) {
    // Clean up stuff after explosion.
    bomb_being_carried = false;
    Glow.Disable(bomb_planted_model);
    
    // Bomb light is parented to bomb_physics and it will be destroyed with it.
    bomb_physics.Destroy();

    bomb_planted        = false;
    bomb_planted_model  = null;
    bomb_physics        = null;

}, "bomb_exploded");

::check_if_planted_bomb_is_on_site <- function() {
    // Before one tick of bomb explosion, check if bomb is on target bomb sites, if it's not - give win to CT.
    //
    // @note: I don't really know about order of execution of CS:GO code (and VS.Library timer), but I think there is a chance that bomc
    // can be defused on last tick before explosion and this function will go first and break economy for CT with
    // confusing message about "preventing explosion on bombsite".
    //
    // I can only hope that this will "never" happen, he-he.
    if (!is_bomb_defused && !round_ended) {
        // We need to pass to game_round_end float value that represents timer before starting new round.
        // If you pass zero, game_round_end will not trigger.
        local how_much_to_wait_before_starting_new_round = 10.0; // This is default in CS:GO Competitive. Maybe it's different in Casual, I don't care really.

        if (bomb_terrorists_allowed_to_win) {
            // EntFire("game_round_end", "EndRound_TerroristsWin", how_much_to_wait_before_starting_new_round);
        } else {
            EntFire("game_round_end", "EndRound_CounterTerroristsWin", how_much_to_wait_before_starting_new_round);
            
            // @note: If T didn't plant the bomb and ran out of the round time they will get 0 money.
            // Potentially they could plant the bomb at respawn, wait for explosion and get losing money.
            // I think I'm fine with that idea.

            // Decide how much money to give to CT in different game modes.
            local how_much_to_give = 1700;
            local game_mode = ScriptGetGameMode(); // If we planted the bomb, this is probably game type "0", so we will only check the game mode.
            if (game_mode == 0) {        // Casual.
                how_much_to_give = 2400;
            } else if (game_mode == 1) { // Competitive.
                how_much_to_give = 1700;
            } else if (game_mode == 2) { // Wingman.
                how_much_to_give = 2200;
            }

            // Give money to CT.
            local money = VS.CreateEntity("game_money", {
                Money       = how_much_to_give,
                AwardText   = "Team award for winning by preventing explosion on bombsite."
            });

            EntFireByHandle(money, "AddTeamMoneyCT");
        }
    }
}

::timer_is_over <- function() {
    bomb_timer_is_over = true;
}

VS.ListenToGameEvent("round_end", function(event) {
    // Imagine situation where T planted the bomb, killed all players on CT, got a win and
    // bomb managed to explode outside of the bombsite before new round, resulting in CT getting extra win.
    // This will not happen, because if someone got a win in a round, you can't give a second win in this same round in CS:GO.
    //
    // But I feel like I want to use this round_ended guard in "check_if_planted_bomb_is_on_site" function anyway.
    round_ended             = true;
    what_team_won_the_round = event.winner;

    if (what_team_won_the_round == terrorists_team) {
        ++t_score;
    } else if (what_team_won_the_round == counter_terrorists_team) {
        ++ct_score;
    }

    // After half time, teams are switched, so we need to switch values of our variables too.
    if (last_round_of_half_match) {
        local buffer = t_score;
        t_score = ct_score;
        ct_score = buffer;
    }

    // Chat("Round end! Winner = " + event.winner);

}, "round_end");

::air_boost_grenades <- function() {
    // @note: Dropped weapons don't have velocity in GetVelocity function, so they will not work with air boost.
    local array_size = air_boost_array.len();

    if (array_size > 0) {
        for (local i = 0; i < array_size; ++i) {
            local start_point     = air_boost_array[i].start_point;
            local last_point      = air_boost_array[i].last_point;
            local new_point       = air_boost_array[i].new_point;
            local stuck_ticks     = air_boost_array[i].stuck_ticks;
            local max_stuck_ticks = air_boost_array[i].max_stuck_ticks;

            // Check if we stuck, if Z position did not change in certain amount of ticks - we probably hit something.
            local entity_probably_stuck = false;
            local entity_stuck = false;

            if (VS.CloseEnough(new_point, last_point, 0.250)) {
                entity_probably_stuck = true;
            }

            if (entity_probably_stuck) {
                air_boost_array[i].stuck_ticks = stuck_ticks + 1;
            } else {
                air_boost_array[i].stuck_ticks = 0;
            }

            if (stuck_ticks >= max_stuck_ticks) {
                entity_stuck = true;
            }
            
            // If entity is not null and didn't stuck mid air and didn't reach max height and didn't die, continue boosting entity.
            if (air_boost_array[i].entity && !entity_stuck && new_point - start_point < air_boost_array[i].max_boost_height) {
                air_boost_add_velocity(air_boost_array[i]);
            } else {
                // Air boost for the specified entity is finished, delete his data and re-sort array.
                air_boost_array.remove(i);
                --array_size;
                --i;
            }
        }
    }
}

::air_boost_add_velocity <- function(air_boost) {
    local entity = air_boost.entity;

    local boost_speed = air_boost.boost_speed;
    local velocity    = entity.GetVelocity();

    // Change only height velocity.
    local lerp_strength = 0.0;

    if (velocity.z < -130.0) {
        lerp_strength = (velocity.z / 100.0) * -1.0; // If we are falling, add extra speed.
    } else {
        lerp_strength = 1.3;
    }

    lerp_strength = clamp(lerp_strength * dt, 0.0, 1.0);

    local new_height = VS.Lerp(velocity.z, boost_speed, lerp_strength);

    velocity = Vector(velocity.x, velocity.y, new_height);
    entity.SetVelocity(velocity);
    
    local new_point = entity.GetOrigin().z;

    air_boost.last_point = air_boost.new_point; // Need to save last point to check if entity stuck mid air.
    air_boost.new_point  = new_point;
}

VS.ListenToGameEvent("grenade_thrown", function(event) {
    local player = ToExtendedPlayer(VS.GetPlayerByUserid(event.userid));

    if (!player) {
        return;
    }
    
    // Thrown grenade spawns from player's eyes.
    // @todo: hegrenade_detonate event shows who owned this grenade, maybe I could check the owner somehow in the projectile? -- What for?
    local eye_position = player.EyePosition();
    local grenade      = null;
    local find_radius  = 42.0; // 38.0 is the minimum radius to find grenade from eyes, but sometimes it doesn't work.

    // Find what kind of grenade we just threw.
    if (grenade = Entities.FindByClassnameNearest("smokegrenade_projectile", eye_position, find_radius)) {
        spawned_grenade_array.push(grenade.weakref());
    } else if (grenade = Entities.FindByClassnameNearest("hegrenade_projectile", eye_position, find_radius)) {
        spawned_grenade_array.push(grenade.weakref());
    } else if (grenade = Entities.FindByClassnameNearest("molotov_projectile", eye_position, find_radius)) {
        spawned_grenade_array.push(grenade.weakref());
    } else if (grenade = Entities.FindByClassnameNearest("flashbang_projectile", eye_position, find_radius)) {
        spawned_grenade_array.push(grenade.weakref());
    } else if (grenade = Entities.FindByClassnameNearest("decoy_projectile", eye_position, find_radius)) {
        spawned_grenade_array.push(grenade.weakref());
    }

}, "grenade_spawned");

::check_if_grenade_is_in_air_boost_trigger <- function() {
    local grenade_array_size = spawned_grenade_array.len();

    if (grenade_array_size > 0) {
        local trigger_array_size = air_boost_trigger_array.len();

        if (trigger_array_size > 0) {
            for (local i = 0; i < trigger_array_size; ++i) {
                local trigger = air_boost_trigger_array[i];
                local trigger_position = trigger.GetOrigin();
    
                // Get global vectors of mins and maxs of trigger collision. 
                local start = trigger_position + trigger.GetBoundingMins();
                local end   = trigger_position + trigger.GetBoundingMaxs();

                for (local j = 0; j < grenade_array_size; ++j) {
                    local grenade = spawned_grenade_array[j];

                    if (!grenade)
                        continue;

                    local position = grenade.GetOrigin();
                    
                    // If grenade is in trigger, add it to air boost.
                    if (VS.IsPointInBox(position, start, end)) {
                        add_grenade_to_air_boost(grenade);
                    }
                }
            }
        }
    }
}

::add_grenade_to_air_boost <- function(grenade) {
    local air_boost = Air_Boost();
    
    // @note: Source will delete grenade on their own and we need to make it weakref,
    // so that our variable can become null and not just some instance.
    air_boost.entity      = grenade.weakref();
    air_boost.start_point = grenade.GetOrigin().z;

    air_boost_add_velocity(air_boost);

    air_boost_array.push(air_boost);
}

::check_grenade_array <- function() {
    local grenade_array_size = spawned_grenade_array.len();

    if (grenade_array_size > 0) {
        for (local i = 0; i < grenade_array_size; ++i) {
            if (!spawned_grenade_array[i]) {
                // Grenade entity was deleted, delete it from our array and re-sort.
                spawned_grenade_array.remove(i);
                --grenade_array_size;
                --i;
            }
        }
    }
}

VS.ListenToGameEvent("inferno_startburn", function(event) {
    local inferno_id       = event.entityid; // You can use VS.GetEntityByIndex(event.entityid), if you want to get an entity.
    local inferno_position = Vector(event.x, event.y, event.z);
    local light_position   = Vector(event.x, event.y, event.z + 40.0);

    // DebugDrawLine(inferno_position, light_position, 0, 255, 0, false, 2.0);

    local molotov_illume = null;
    local molotov_illume_array_size = molotov_illume_array.len();

    for (local i = 0; i < molotov_illume_array_size; ++i) {
        molotov_illume = molotov_illume_array[i];
        if (!molotov_illume.occupied) {
            // We will increase light distance in update.
            molotov_illume.occupied = true;
            molotov_illume.inferno  = inferno_id;
            molotov_illume.light.SetAbsOrigin(light_position);

            break;
        }
    }

}, "inferno_startburn");

VS.ListenToGameEvent("inferno_expire", function(event) {
    // You can get inferno expire or inferno extinguish, but not both.
    local inferno_id       = event.entityid;
    local inferno_position = Vector(event.x, event.y, event.z);
    local light_position   = Vector(event.x, event.y, event.z + 40.0);

    // DebugDrawLine(inferno_position, light_position, 0, 0, 255, false, 2.0);

    local molotov_illume = null;
    local molotov_illume_array_size = molotov_illume_array.len();

    for (local i = 0; i < molotov_illume_array_size; ++i) {
        molotov_illume = molotov_illume_array[i];
        if (molotov_illume.inferno == inferno_id) {
            // We will fade light in update.
            molotov_illume.fading = true;
            molotov_illume.distance_prior_to_fading = molotov_illume.distance;

            break;
        }
    }

}, "inferno_expire");

VS.ListenToGameEvent("inferno_extinguish", function(event) {
    // You can get inferno expire or inferno extinguish, but not both.
    // @bug: I will just disable the light when we extinguish fire with smoke grenade, because sometimes smoke grenade will land near
    // molotov's fire, play extinguish sound, execute this extinguish event, but the actual fire (inferno) will continue to burn until it's gone.
    local inferno_id       = event.entityid;
    local inferno_position = Vector(event.x, event.y, event.z);
    local light_position   = Vector(event.x, event.y, event.z + 40.0);
    
    // DebugDrawLine(inferno_position, light_position, 255, 0, 0, false, 4.0);

    local molotov_illume = null;
    local molotov_illume_array_size = molotov_illume_array.len();

    for (local i = 0; i < molotov_illume_array_size; ++i) {
        molotov_illume = molotov_illume_array[i];
        if (molotov_illume.inferno == inferno_id) {
            molotov_illume.occupied      = false;
            molotov_illume.inferno       = 0;
            molotov_illume.distance      = 0.0;
            molotov_illume.distance_lerp = 0.0;
            molotov_illume.sprite_scale  = 0.0;

            VS.SetKeyValue(molotov_illume.light, "distance", 0.0);
            EntFireByHandle(molotov_illume.sprite, "HideSprite");

            break;
        }
    }

}, "inferno_extinguish");

::molotov_illumination_update <- function() {
    local molotov_illume = null;
    local molotov_illume_array_size = molotov_illume_array.len();

    for (local i = 0; i < molotov_illume_array_size; ++i) {
        molotov_illume = molotov_illume_array[i];
        if (molotov_illume.occupied) {
            if (!molotov_illume.fading) { // Fire started to burn - increase the light distance.
                if (VS.CloseEnough(molotov_illume.distance_lerp, 1.0, 0.01))
                    continue;
    
                local lerp_speed = dt * 0.2;
                lerp_speed = clamp(lerp_speed, 0.0, 1.0);
                
                molotov_illume.distance_lerp = VS.Lerp(molotov_illume.distance_lerp, 1.0, lerp_speed);
                local easing_value           = ease_out_circ(molotov_illume.distance_lerp);
                molotov_illume.distance      = easing_value * molotov_illume.max_distance;
    
                VS.SetKeyValue(molotov_illume.light, "distance", molotov_illume.distance);
                
                // Sprite scale can not be zero, need to wait some time and after that gradually scale the sprite.
                if (molotov_illume.distance_lerp >= 0.02) {
                    if (molotov_illume.sprite_scale >= molotov_illume.sprite_max_scale) // If we got to the max scale, don't do anything.
                        continue;

                    EntFireByHandle(molotov_illume.sprite, "ShowSprite");

                    local scale_time = 0.3 / dt;
                    molotov_illume.sprite_scale += molotov_illume.sprite_max_scale / scale_time;
                    VS.SetKeyValue(molotov_illume.sprite, "scale", molotov_illume.sprite_scale);
                }
        } else { // Fire is fading - decrease the light.
                if (molotov_illume.distance <= 0.0) {
                    molotov_illume.occupied                 = false;
                    molotov_illume.fading                   = false;
                    molotov_illume.inferno                  = 0;
                    molotov_illume.distance                 = 0.0;
                    molotov_illume.distance_prior_to_fading = 0.0;
                    molotov_illume.distance_lerp            = 0.0;
                    molotov_illume.sprite_scale             = 0.0;
    
                    VS.SetKeyValue(molotov_illume.light, "distance", 0.0);
                    EntFireByHandle(molotov_illume.sprite, "HideSprite");

                    continue;
                }
    
                local fade_time = 0.9 / dt; // Formula: time_you_want_to_fade_to_zero_in_seconds / delta_time. 
                molotov_illume.distance -= molotov_illume.distance_prior_to_fading / fade_time;

                VS.SetKeyValue(molotov_illume.light, "distance", molotov_illume.distance);

                // Need to scale down the sprite and hide it almost at the end of fire burn.
                if (molotov_illume.distance <= 90.0) {
                    molotov_illume.sprite_scale = 0.0;
                    EntFireByHandle(molotov_illume.sprite, "HideSprite");
                } else {
                    local scale_time = 0.6 / dt;
                    molotov_illume.sprite_scale -= molotov_illume.sprite_max_scale / scale_time;
                    VS.SetKeyValue(molotov_illume.sprite, "scale", molotov_illume.sprite_scale);
                }
            }
        }

    }
}

::bonus_case_t_just_broke <- function() {
    bonus_case_t_broke = true;
}

::bonus_case_ct_just_broke <- function() {
    bonus_case_ct_broke = true;
}

::comeback_bonus_case_update <- function() {
    // Check Terrorists bonus.
    if (!bonus_t_given) {
        if (bonus_case_t_broke) {
            bonus_t_given = true;
    
            local case_origin = bonus_case_t_origin;
            local case_center = bonus_case_t_center;
            give_bonus(case_origin, case_center, 2);
        } else {
            if (bonus_case_t.IsValid()) {
                bonus_case_t_origin = bonus_case_t.GetOrigin();
                bonus_case_t_center = bonus_case_t.GetCenter();
            }
        }
    }

    // Check Counter-Terrorists bonus.
    if (!bonus_ct_given) {
        if (bonus_case_ct_broke) {
            bonus_ct_given = true;
    
            local case_origin = bonus_case_ct_origin;
            local case_center = bonus_case_ct_center;
            give_bonus(case_origin, case_center, 3);
        } else {
            if (bonus_case_ct.IsValid()) {
                bonus_case_ct_origin = bonus_case_ct.GetOrigin();
                bonus_case_ct_center = bonus_case_ct.GetCenter();
            }
        }
    }
}

::give_bonus <- function(case_origin, case_center, team_number) {
    // We will always give 5 healthshots and 1 breachcharge.
    // @note: VS.CreateEntity only creates entities, it doesn't spawn them. Need to make them through template.
    healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 8.0, -8.0), Vector());
    healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 4.0, -8.0), Vector());
    healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 0.0, -8.0), Vector());
    healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, -4.0, -8.0), Vector());
    healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, -8.0, -8.0), Vector());

    breachcharge_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 0.0, 8.0), Vector());

    // We also add some extra bonus items to the case with a random drop chance.
    // Glow color.    Chance range.    The bonus.
    // Green          55  -  100       -- 20 stacks of $50 banknotes that give $1000 in total.
    // Blue           35  -  55        -- 5 extra healthshots.
    // Red            20  -  35        -- 1 extra breachcharge.
    // Purple         10  -  20        -- 5 tagrenades.
    // Gold           0.5 -  10        -- 1 heavy armor.
    // White          0   -  0.5       -- Huge invincible chicken as an easter egg.
    local random_number = RandomFloat(0.0, 100.0);
    
    local money_spawned = false;
    local tagrenade_spawned = false;

    if (random_number >= 55.0) {
        money_spawned = true;
        local max_stacks = RandomInt(20, 30);
        for (local i = 0; i < max_stacks; ++i) {
            cash_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 0.0, i), Vector());
        }
    } else if (random_number >= 35.0) {
        healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(-4.0, 8.0, 8.0), Vector());
        healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(-4.0, 4.0, 8.0), Vector());
        healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(-4.0, 0.0, 8.0), Vector());
        healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(-4.0, -4.0, 8.0), Vector());
        healthshot_spawner.SpawnEntityAtLocation(case_center + Vector(-4.0, -8.0, 8.0), Vector());
    } else if (random_number >= 20.0) {
        breachcharge_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, -8.0, 16.0), Vector());
    } else if (random_number >= 10.0) {
        tagrenade_spawned = true;
        tagrenade_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 8.0, 0.0), Vector());
        tagrenade_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 4.0, 0.0), Vector());
        tagrenade_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, 0.0, 0.0), Vector());
        tagrenade_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, -4.0, 0.0), Vector());
        tagrenade_spawner.SpawnEntityAtLocation(case_center + Vector(0.0, -8.0, 0.0), Vector());
    } else if (random_number >= 0.5) {
        // @bug: If you pick up heavy armor you can not pick up rifles in all game modes, except "Guardian" and "Co-op Strike",
        // but you can still carry a rifle, if player carried one before picking up heavy armor.
        // In CS:GO you can not force players to drop their weapons and items, even with "game_player_equip" entity, this entity just deletes the items.
        // You can try to delete the rifles and spawn a new one under the player, but you also need to somehow copy player's weapon skins, stickers and so on.
        //
        // My decision is: I will do nothing about this bug, I do not agree with Valve's decision to restrict rifles with heavy armor, so I'll leave
        // players with an option to able to carry a rifle, even if the game will warn players that they can not pick up a rifle, if player will look at a dropped rifle.
        local heavy_armor = null;

        if (team_number == terrorists_team) {
            heavy_armor = Entities.FindByName(null, "heavyarmor_t");
            heavy_armor.SetAbsOrigin(case_origin);
            heavy_armor.SetForwardVector(Vector(1,0,0));
            heavy_armor.SetAngles(0.0, RandomFloat(-180.0, 180.0), 0.0); // We will randomly rotate armor around Z (angles are read as YZX).
            Glow.Set(heavy_armor, "255 163 9", 0, 1024.0);
        } else {
            heavy_armor = Entities.FindByName(null, "heavyarmor_ct");
            heavy_armor.SetAbsOrigin(case_origin);
            heavy_armor.SetForwardVector(Vector(1,0,0));
            heavy_armor.SetAngles(0.0, RandomFloat(-180.0, 180.0), 0.0);
            Glow.Set(heavy_armor, "255 163 9", 0, 1024.0);
        }
    } else if (random_number >= 0.0) {
        local chicken = null;
        
        if (team_number == terrorists_team) {
            chicken = Entities.FindByName(null, "chicken_freeman");
            chicken.SetAbsOrigin(case_center);
            Glow.Set(chicken, "255 254 232", 0, 1024.0);
        } else {
            chicken = Entities.FindByName(null, "chicken_gordon");
            chicken.SetAbsOrigin(case_center);
            Glow.Set(chicken, "255 254 232", 0, 1024.0);
        }
    }

    // Chat("Random = " + random_number);

    // Need to set glow for bonus items, so that players could see them clearly.
    if (money_spawned) {
        local money = null;
        while (money = Entities.FindByClassname(money, "item_cash")) {
            Glow.Set(money, "45 247 34", 0, 1024.0);
        }
    }

    local healthshot = null;
    while (healthshot = Entities.FindByClassname(healthshot, "weapon_healthshot")) {
        if (!healthshot.GetMoveParent()) // If someone holds bonus item that player got in previous rounds - do not glow.
            Glow.Set(healthshot, "35 216 254", 0, 1024.0);
    }

    local breachcharge = null;
    while (breachcharge = Entities.FindByClassname(breachcharge, "weapon_breachcharge")) {
        if (!breachcharge.GetMoveParent())
            Glow.Set(breachcharge, "250 48 12", 0, 1024.0);
    }

    if (tagrenade_spawned) {
        local tagrenade = null;
        while (tagrenade = Entities.FindByClassname(tagrenade, "weapon_tagrenade")) {
            if (!tagrenade.GetMoveParent())
                Glow.Set(tagrenade, "239 67 235", 0, 1024.0);
        }
    }

    // Disable glow on all bonus items after some time.
    VS.Timer(0, 9.0, disable_glow_on_bonus_items);
}

::equip_player_with_heavy_armor <- function(player) {
    // When you pick up heavy armor, player's world model changes to heavy armor,
    // but his viemodel is not - need to manually change model of player's viewmodel (firstperson arms).
    // @note: You don't need to set new model for viewmodel through viewmodel entity, you can do this through player entity.
    if (player.GetTeam() == terrorists_team) {
        player.SetModel("models/weapons/v_models/arms/phoenix_heavy/v_sleeve_phoenix_heavy.mdl");
    } else {
        player.SetModel("models/weapons/v_models/arms/ctm_heavy/v_sleeve_ctm_heavy.mdl");
    }
    
    heavyarmor_spawner.SpawnEntityAtLocation(player.GetOrigin(), Vector());
}

::disable_glow_on_bonus_items <- function() {
    if (!bonus_glow_disabled) {
        bonus_glow_disabled = true;

        local money = null;
        while (money = Entities.FindByClassname(money, "item_cash")) {
            Glow.Disable(money);
        }

        local healthshot = null;
        while (healthshot = Entities.FindByClassname(healthshot, "weapon_healthshot")) {
            Glow.Disable(healthshot);
        }

        local breachcharge = null;
        while (breachcharge = Entities.FindByClassname(breachcharge, "weapon_breachcharge")) {
            Glow.Disable(breachcharge);
        }

        local tagrenade = null;
        while (tagrenade = Entities.FindByClassname(tagrenade, "weapon_tagrenade")) {
            Glow.Disable(tagrenade);
        }

        Glow.Disable(Entities.FindByName(null, "heavyarmor_t"));
        Glow.Disable(Entities.FindByName(null, "heavyarmor_ct"));

        Glow.Disable(Entities.FindByName(null, "chicken_freeman"));
        Glow.Disable(Entities.FindByName(null, "chicken_gordon"));
    }
}

::play_music_from_speaker <- function() {
    if (!speaker_activated) {
        speaker_activated = true;

        local vinyl_sound = Entities.FindByName(null, "vinyl");
        EntFireByHandle(vinyl_sound, "PlaySound");
    }
}

::save_firearms_list <- function() {
    firearms_array.push("ak47");
    firearms_array.push("aug");
    firearms_array.push("awp");
    firearms_array.push("bizon");
    firearms_array.push("cz75a");
    firearms_array.push("deagle");
    firearms_array.push("elite");
    firearms_array.push("famas");
    firearms_array.push("fiveseven");
    firearms_array.push("g3sg1");
    firearms_array.push("galilar");
    firearms_array.push("glock");
    firearms_array.push("hkp2000");
    firearms_array.push("m249");
    firearms_array.push("m4a1");
    firearms_array.push("mac10");
    firearms_array.push("mag7");
    firearms_array.push("mp5sd");
    firearms_array.push("mp7");
    firearms_array.push("mp9");
    firearms_array.push("negev");
    firearms_array.push("nova");
    firearms_array.push("p250");
    firearms_array.push("p90");
    firearms_array.push("revolver");
    firearms_array.push("sawedoff");
    firearms_array.push("scar20");
    firearms_array.push("sg556");
    firearms_array.push("ssg08");
    firearms_array.push("taser");
    firearms_array.push("tec9");
    firearms_array.push("ump45");
    firearms_array.push("xm1014");
}

::ease_out_circ <- function(x) {
    return sqrt(1 - pow(x - 1, 2));
}