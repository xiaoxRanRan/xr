// *************************************************************************
//  This file is part of SourceBans++.
//
//  Copyright (C) 2014-2024 SourceBans++ Dev Team <https://github.com/sbpp>
//
//  SourceBans++ is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, per version 3 of the License.
//
//  SourceBans++ is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with SourceBans++. If not, see <http://www.gnu.org/licenses/>.
//
//  This file based off work(s) covered by the following copyright(s):
//
//   SourceComms 0.9.266
//   Copyright (C) 2013-2014 Alexandr Duplishchev
//   Licensed under GNU GPL version 3, or later.
//   Page: <https://forums.alliedmods.net/showthread.php?p=1883705> - <https://github.com/d-ai/SourceComms>
//
// *************************************************************************

#if defined _sourcecomms_included
#endinput
#endif
#define _sourcecomms_included

#define SBPPComms_VERSION_MAJOR "1"
#define SBPPComms_VERSION_MINOR "8"
#define SBPPComms_VERSION_PATCH "3"

#define SBPPComms_VERSION   SBPPComms_VERSION_MAJOR..."."...SBPPComms_VERSION_MINOR..."."...SBPPComms_VERSION_PATCH

/**
 * @section Int definitions for punishments types.
 */

#define TYPE_MUTE           1   /**< Voice Mute */
#define TYPE_GAG            2   /**< Gag (text chat) */
#define TYPE_SILENCE        3   /**< Silence (mute + gag) */
#define TYPE_UNMUTE         4   /**< Voice Unmute*/
#define TYPE_UNGAG          5   /**< Ungag*/
#define TYPE_UNSILENCE      6   /**< Unsilence */
#define TYPE_TEMP_UNMUTE    14  /**< Temp mute removed */
#define TYPE_TEMP_UNGAG     15  /**< Temp gag removed */
#define TYPE_TEMP_UNSILENCE 16  /**< Temp silence removed */

/* Punishments types */
enum bType {
	bNot = 0,  // Player chat or voice is not blocked
	bSess,  // ... blocked for player session (until reconnect)
	bTime,  // ... blocked for some time
	bPerm // ... permanently blocked
}

/**
 * Sets a client's mute state.
 *
 * @param client		Client index.
 * @param muteState		True to mute client, false to unmute.
 * -------------------------------------Parameters below this line are used only for muteState=true-------------------------------------
 * ----------------------------------for muteState=false these parameters are ignored (saveToDB=false)----------------------------------
 * @param muteLength		Length of punishment in minutes. Value < 0 muting client for session. Permanent (0) is not allowed at this time.
 * @param saveToDB		If true, punishment will be saved in database.
 * @param reason		Reason for punishment.
 * @return				True if this caused a change in mute state, false otherwise.
 */
native bool SourceComms_SetClientMute(int client, bool muteState, int muteLength = -1, bool saveToDB = false, const char[] reason = "Muted through natives");

/**
 * Sets a client's gag state.
 *
 * @param client		Client index.
 * @param gagState		True to gag client, false to ungag.
 * --------------------------------------Parameters below this line are used only for gagState=true--------------------------------------
 * -----------------------------------for gagState=false these parameters are ignored (saveToDB=false)-----------------------------------
 * @param gagLength		Length of punishment in minutes. Value < 0 gagging client for session. Permanent (0) is not allowed at this time.
 * @param saveToDB		If true, punishment will be saved in database.
 * @param reason		Reason for punishment.
 * @return				True if this caused a change in gag state, false otherwise.
 */
native bool SourceComms_SetClientGag(int client, bool gagState, int gagLength = -1, bool saveToDB = false, const char[] reason = "Gagged through natives");

/**
 * Returns the client's mute type
 *
 * @param client	The client index of the player to check mute status
 * @return          The client's current mute type index (see enum bType in the begin).
 */
native bType SourceComms_GetClientMuteType(int client);


/**
 * Returns the client's gag type
 *
 * @param client	The client index of the player to check gag status
 * @return          The client's current gag type index (see enum bType in the begin).
 */
native bType SourceComms_GetClientGagType(int client);

/**
 * Called when added communication block for player.
 *
 * @param client	The client index of the admin who is blocking the client.
 * @param target	The client index of the player to blocked.
 * @param time		The time to blocked the player for (in minutes, 0 = permanent).
 * @param type		The type of block. See section "Int definitions for punishments types".
 * @param reason	The reason to block the player.
 */
forward void SourceComms_OnBlockAdded(int client, int target, int time, int type, char[] reason);

/**
 * Called when removed communication block for player.
 *
 * @param client	The client index of the admin who is unblocking the client.
 * @param target	The client index of the player to blocked.
 * @param type		The type of unblock. See section "Int definitions for punishments types".
 * @param reason	The reason to unblock the player.
 */
forward void SourceComms_OnBlockRemoved(int client, int target, int type, char[] reason);

public SharedPlugin __pl_sourcecomms =
{
	name = "sourcecomms++",
	file = "sbpp_comms.smx",
	#if defined REQUIRE_PLUGIN
	required = 1
	#else
	required = 0
	#endif
};

public void __pl_sourcecomms_SetNTVOptional()
{
	MarkNativeAsOptional("SourceComms_SetClientMute");
	MarkNativeAsOptional("SourceComms_SetClientGag");
	MarkNativeAsOptional("SourceComms_GetClientMuteType");
	MarkNativeAsOptional("SourceComms_GetClientGagType");
}
