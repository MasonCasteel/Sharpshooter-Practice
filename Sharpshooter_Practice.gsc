// T6 GSC SOURCE
// Buried Sharpshooter (last easter egg step) practice script
//
// - Hold USE (about 1 second) anywhere to start the target run
// - Everyone spawns with MP5 + PDW-57 (starting pistol removed, 2 gun limit) and max points
// - All doors / debris / airlock gates are opened and all window barriers are broken at start
// - The barricades Leroy (Sloth) has to break are removed at start
// - Regular zombies never spawn
// - Chat commands: 1p = 20 targets, 2p = 39, 3p = 61, 4p = 84,
//   0p or reset = default for the current player count, speed = toggle Speed Cola
//   (for yourself), help = list the commands
// - Everyone gets max ammo when a run ends
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_audio;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zm_buried_sq;
#include maps\mp\zm_buried_sq_ows;
#include maps\mp\zombies\_zm_sidequests;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

main()
{
    replacefunc( ::ows_targets_start, ::ows_targets_start2 );
    replacefunc( ::sndhit, ::sndhitnew );

    flag_wait( "initial_blackscreen_passed" );

    level thread targetsleft();
    level thread sp_open_all_doors();
    level thread maps\mp\zombies\_zm_blockers::open_all_zbarriers();
    level thread sp_remove_sloth_barricades();
    level thread sp_block_zombie_spawns();
    level thread sp_chat_commands();

    // Runs are started by holding USE (see sp_watch_use_hold), which sets this flag.
    while ( true )
    {
        flag_wait( "sq_ows_start" );
        ows_targets_start2();
        flag_clear( "sq_ows_start" );
    }
}

init()
{
    level.inital_spawn = 1;
    level.targettohit = 0;
    level.sp_run_active = 0;
    level.sp_target_override = 0;   // 0 = use the player-count default
    level.sp_hold_time = 1.0;       // seconds you have to hold USE to start a run
    level.sp_max_points = 1000000;  // points everyone is topped up to on spawn
    thread onplayerconnect();
}

onplayerconnect()
{
    while ( true )
    {
        level waittill( "connecting", player );

        player thread onplayerspawned();
        player thread sp_watch_use_hold();
    }
}

onplayerspawned()
{
    level endon( "game_ended" );
    self endon( "disconnect" );
    self.initial_spawn = 1;

    for (;;)
    {
        self waittill( "spawned_player" );

        self iprintln( "^4Sharpshooter Practice" );
        self iprintln( "^7Type ^2help ^7in chat for the command list" );
        self thread sp_give_loadout();
    }
}

// ---------------------------------------------------------------------
// Loadout / points
// ---------------------------------------------------------------------

sp_give_loadout()
{
    self endon( "disconnect" );

    // let the game finish its own spawn loadout first
    wait 1;

    if ( !isalive( self ) )
        return;

    // The game only allows 2 primary weapons (3 with Mule Kick). Going over makes the
    // too-many-weapons monitor take your guns AND zero your points, so the starting
    // pistol has to be removed before MP5 + PDW are added.
    if ( isdefined( level.start_weapon ) && self hasweapon( level.start_weapon ) )
        self takeweapon( level.start_weapon );

    self maps\mp\zombies\_zm_weapons::weapon_give( "mp5k_zm", 0, 0, 1 );
    self maps\mp\zombies\_zm_weapons::weapon_give( "pdw57_zm", 0, 0, 1 );
    self givemaxammo( "mp5k_zm" );
    self givemaxammo( "pdw57_zm" );
    self switchtoweapon( "mp5k_zm" );

    if ( self.score < level.sp_max_points )
        self maps\mp\zombies\_zm_score::add_to_player_score( level.sp_max_points - self.score );
}

// ---------------------------------------------------------------------
// Doors
// ---------------------------------------------------------------------

sp_open_all_doors()
{
    players = get_players();

    if ( players.size < 1 )
        return;

    opener = players[0];

    // notify( "trigger", player, 1 ) is the same forced open the quantum bomb uses:
    // no cost, no USE check.
    zombie_doors = getentarray( "zombie_door", "targetname" );

    foreach ( door in zombie_doors )
    {
        door notify( "trigger", opener, 1 );
        wait 0.05;
    }

    airlock_doors = getentarray( "zombie_airlock_buy", "targetname" );

    foreach ( door in airlock_doors )
    {
        door notify( "trigger", opener, 1 );
        wait 0.05;
    }

    debris = getentarray( "zombie_debris", "targetname" );

    foreach ( junk in debris )
    {
        if ( isdefined( junk ) )
            junk notify( "trigger", opener, 1 );

        wait 0.05;
    }
}

// ---------------------------------------------------------------------
// Leroy (Sloth) barricades
// ---------------------------------------------------------------------

// Does what the game does when Sloth breaks a barricade (see watch_barricade in
// _zm_ai_sloth): sets the barricade's flag, sends the same level notifies, and
// removes the pieces. Barricades marked "no_delete" are hidden instead, because
// the game re-shows those later.
sp_remove_sloth_barricades()
{
    triggers = getentarray( "sloth_barricade", "targetname" );

    foreach ( trig in triggers )
    {
        should_delete = !isdefined( trig.script_string ) || trig.script_string != "no_delete";

        if ( isdefined( trig.script_flag ) && level flag_exists( trig.script_flag ) )
        {
            flag_set( trig.script_flag );

            if ( trig.script_flag == "jail_door1" )
                level notify( "jail_barricade_down" );
        }

        if ( isdefined( trig.script_noteworthy ) && trig.script_noteworthy == "courtyard_fountain" )
            level notify( "courtyard_fountain_open" );

        if ( isdefined( trig.script_int ) )
            exploder( trig.script_int );

        if ( isdefined( trig.target ) )
        {
            pieces = getentarray( trig.target, "targetname" );

            foreach ( piece in pieces )
            {
                if ( should_delete )
                    piece delete();
                else
                    piece maps\mp\zombies\_zm_ai_sloth::hide_sloth_barrier();
            }
        }

        if ( should_delete )
            trig delete();
        else
            trig maps\mp\zombies\_zm_ai_sloth::hide_sloth_barrier();
    }
}

// ---------------------------------------------------------------------
// No zombie spawns
// ---------------------------------------------------------------------

// The game's round_spawning() only spawns while get_current_zombie_count() is below
// level.zombie_ai_limit, so a limit of 0 means regular zombies never spawn. The round
// never ends either (zombie_total stays above 0), so the round number stays put.
sp_block_zombie_spawns()
{
    while ( true )
    {
        level.zombie_ai_limit = 0;
        wait 1;
    }
}

// ---------------------------------------------------------------------
// Hold USE anywhere to start the run
// ---------------------------------------------------------------------

sp_watch_use_hold()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    self waittill( "spawned_player" );

    held = 0;

    for (;;)
    {
        wait 0.05;

        if ( !isalive( self ) || self.sessionstate != "playing" || self maps\mp\zombies\_zm_laststand::player_is_in_laststand() || self in_revive_trigger() || !self usebuttonpressed() )
        {
            held = 0;
            continue;
        }

        held = held + 0.05;

        if ( held < level.sp_hold_time )
            continue;

        held = 0;

        if ( is_true( level.sp_run_active ) )
            self iprintln( "^1Run already in progress" );
        else
        {
            level.sp_run_active = 1;
            self iprintln( "^2Sharpshooter started" );
            flag_set( "sq_ows_start" );
        }

        // one hold = one start, wait for the button to be released
        while ( self usebuttonpressed() )
            wait 0.05;
    }
}

// ---------------------------------------------------------------------
// Target run (practice copy of the game's ows_targets_start)
// ---------------------------------------------------------------------

sp_set_target_count()
{
    if ( level.sp_target_override > 0 )
    {
        level.targettohit = level.sp_target_override;
        return;
    }

    players = get_players();

    if ( players.size == 1 )
        level.targettohit = 20;
    else if ( players.size == 2 )
        level.targettohit = 39;
    else if ( players.size == 3 )
        level.targettohit = 61;
    else if ( players.size >= 4 )
        level.targettohit = 84;
}

// ---------------------------------------------------------------------
// Chat commands: 0p / 1p / 2p / 3p / 4p / reset / speed / help
// ---------------------------------------------------------------------

sp_show_help()
{
    self endon( "disconnect" );

    self iprintln( "^3Hold INTERACT (use) to start Sharpshooter" );
    self iprintln( "^5Chat commands:" );
    self iprintln( "^21p ^7= 20 targets   ^22p ^7= 39   ^23p ^7= 61   ^24p ^7= 84" );
    self iprintln( "^20p ^7or ^2reset ^7= default for player count" );
    self iprintln( "^2speed ^7= toggle Speed Cola (you)" );
    self iprintln( "^2help ^7= show this list" );
}

sp_toggle_speed()
{
    self endon( "disconnect" );

    if ( !isalive( self ) )
        return;

    if ( self hasperk( "specialty_fastreload" ) )
    {
        // same notify the game uses when a perk is lost
        self notify( "specialty_fastreload_stop" );
        self iprintln( "^1Speed Cola off" );
    }
    else
    {
        self thread maps\mp\zombies\_zm_perks::give_perk( "specialty_fastreload", 0 );
        self iprintln( "^2Speed Cola on" );
    }
}

sp_parse_command( msg )
{
    msg = tolower( msg );

    if ( msg == "0p" || msg == "1p" || msg == "2p" || msg == "3p" || msg == "4p" || msg == "reset" || msg == "help" || msg == "speed" )
        return msg;

    return "";
}

sp_chat_commands()
{
    level endon( "game_ended" );

    while ( true )
    {
        level waittill( "say", message, player );

        cmd = sp_parse_command( message );

        // chat messages can arrive with a junk first character
        if ( cmd == "" && isdefined( message ) && message.size > 1 )
            cmd = sp_parse_command( getsubstr( message, 1 ) );

        if ( cmd == "" )
            continue;

        if ( cmd == "help" )
        {
            if ( isdefined( player ) )
                player thread sp_show_help();

            continue;
        }

        if ( cmd == "speed" )
        {
            if ( isdefined( player ) )
                player thread sp_toggle_speed();

            continue;
        }

        if ( cmd == "1p" )
            level.sp_target_override = 20;
        else if ( cmd == "2p" )
            level.sp_target_override = 39;
        else if ( cmd == "3p" )
            level.sp_target_override = 61;
        else if ( cmd == "4p" )
            level.sp_target_override = 84;
        else
            level.sp_target_override = 0;

        if ( is_true( level.sp_run_active ) )
        {
            if ( isdefined( player ) )
                player iprintln( "^3Targets saved, applies next run" );
        }
        else
        {
            sp_set_target_count();

            if ( isdefined( player ) )
                player iprintln( "^2Targets set to " + level.targettohit );
        }
    }
}

ows_targets_start2()
{
    level.sp_run_active = 1;
    sp_set_target_count();

    n_cur_second = 0;
    flag_clear( "sq_ows_target_missed" );
    level thread sndsidequestowsmusic();

    while ( n_cur_second < 40 )
    {
        a_spawn_spots = ows_targets_get_cur_spots( n_cur_second );

        if ( isdefined( a_spawn_spots ) && a_spawn_spots.size > 0 )
            ows_targets_spawn( a_spawn_spots );

        wait 1;
        n_cur_second++;
    }

    if ( !flag( "sq_ows_target_missed" ) )
        playsoundatposition( "zmb_sq_target_success", ( 0, 0, 0 ) );
    else
        playsoundatposition( "zmb_sq_target_fail", ( 0, 0, 0 ) );

    level notify( "sndEndOWSMusic" );
    level.sp_run_active = 0;

    sp_give_max_ammo_all();
}

sp_give_max_ammo_all()
{
    foreach ( player in get_players() )
    {
        if ( !isalive( player ) )
            continue;

        foreach ( weapon in player getweaponslistprimaries() )
            player givemaxammo( weapon );
    }
}

sndhitnew()
{
    self endon( "ows_target_timeout" );

    self waittill( "damage" );

    level.targettohit--;

    self playsound( "zmb_sq_target_hit" );
}

targetsleft()
{
    level.targetshud = createserverfontstring( "hudsmall", 1.9 );
    level.targetshud setpoint( "CENTER", "CENTER", "CENTER", 190 );
    level.targetshud.label = &"^3Targets Left: ^2";

    while ( true )
    {
        level.targetshud setvalue( level.targettohit );
        wait 0.05;
    }
}
