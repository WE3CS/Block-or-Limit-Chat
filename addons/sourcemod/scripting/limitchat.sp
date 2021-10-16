#include <sourcemod>
#pragma semicolon 1

#define PLUGIN_VERSION "1.0.2"

public Plugin:myinfo = 
{
	name = "Block / Limit Chat",
	author = "Sheepdude",
	description = "Limit chat to a specific list of phrases or only for admins and select players.",
	version = PLUGIN_VERSION,
	url = "http://www.clan-psycho.com"
};

new Handle:h_cvarEnable;
new Handle:h_cvarAdmins;
new Handle:h_cvarRequest;
new Handle:h_cvarNeeded;

new bool:g_cvarEnable;
new bool:g_cvarAdmins;
new bool:g_cvarRequest;
new Float:g_cvarNeeded;

new String:AllowedPhrases[128][64];
new bool:AllowedToChat[MAXPLAYERS+1];
new bool:RequestedChat[MAXPLAYERS+1];
new linecount;

public OnPluginStart()
{
	CreateConVar("sm_limitchat_version", PLUGIN_VERSION, "Block / Limit Chat plugin version", FCVAR_DONTRECORD|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_SPONLY);
	h_cvarEnable = CreateConVar("sm_limitchat_enable", "1", "Enable plugin (1 - enable, 0 - disable)", 0, true, 0.0, true, 1.0);
	h_cvarAdmins = CreateConVar("sm_limitchat_admins", "1", "Admins are automatically allowed to chat (1 - admins can chat, 0 - chat restricted)", 0, true, 0.0, true, 1.0);
	h_cvarRequest = CreateConVar("sm_limitchat_request", "1", "Allow requests for chat permission (1 - allow, 0 - disallow)", 0, true, 0.0, true, 1.0);
	h_cvarNeeded = CreateConVar("sm_limitchat_needed", "0.55", "Percentage of admin votes required to grant chat permission", 0, true, 0.0, true, 2.0);
	
	AutoExecConfig();
	
	RegConsoleCmd("sm_requestchat", RequestChat);
	RegAdminCmd("sm_limitchat_give", GiveChat, ADMFLAG_GENERIC, "Grants players permission to chat.");
	RegAdminCmd("sm_limitchat_take", TakeChat, ADMFLAG_GENERIC, "Denies players permission to chat.");
	
	HookConVarChange(h_cvarEnable, ConvarChanged);
	HookConVarChange(h_cvarAdmins, ConvarChanged);
	HookConVarChange(h_cvarRequest, ConvarChanged);
	HookConVarChange(h_cvarNeeded, ConvarChanged);
	
	AddCommandListener(OnSayCommand, "say");
	
	ReadTextFile();
}

/**********
 *Forwards*
***********/

public OnConfigsExecuted()
{
	UpdateAllConvars();
	for(new i = 1; i <= MaxClients; i++)
	{
		RequestedChat[i] = false;
		AllowedToChat[i] = false;
	}
	if(g_cvarAdmins)
		AllowAdminChat();
}

public OnClientPostAdminCheck(client)
{
	if(IsClientInGame(client) && g_cvarAdmins && CheckCommandAccess(client, "limitchat", ADMFLAG_GENERIC, true))
		AllowedToChat[client] = true;
}

/**********
 *Commands*
***********/

public Action:OnSayCommand(client, const String:command[], args)
{
	if(!IsClientInGame(client) || AllowedToChat[client])
		return Plugin_Continue;
	decl String:text[192];
	if (!GetCmdArgString(text, sizeof(text)))
		return Plugin_Stop;
	new startidx = 0;
	if(text[strlen(text)-1] == '"')
	{
		text[strlen(text)-1] = '\0';
		startidx = 1;
	}
	if(!IsValidPhrase(text, startidx))
	{
		PrintToChat(client, "[\x04我为C狂\x01]本服禁止公屏聊天！");
		return Plugin_Stop;
	}
	return Plugin_Continue;	
}

public Action:RequestChat(client, args)
{
	if(!g_cvarRequest)
		return Plugin_Handled;
	if(args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_requestchat <reason>");
		return Plugin_Handled;
	}
	if(RequestedChat[client])
	{
		ReplyToCommand(client, "[SM] You may only request chat permission once per map.");
		return Plugin_Handled;
	}
	if(IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote is in progress, please wait to use this command.");
		return Plugin_Handled;
	}
	decl String:argstring[64];
	GetCmdArgString(argstring, sizeof(argstring));
	DoVoteMenu(client, argstring);
	return Plugin_Handled;
}

/****************
 *Admin Commands*
*****************/

public Action:GiveChat(client, args)
{
	if(args > 0)
	{
		if(CheckCommandAccess(client, "sm_limitchat_give", ADMFLAG_GENERIC, true))
		{
			decl String:target[64];
			new targetlist[MAXPLAYERS+1];
			GetCmdArg(1, target, sizeof(target));
			if(FindMatchingPlayers(target, targetlist) == 0)
			{
				new targetindex = FindTarget(client, target);
				if(targetindex > 0)
				{
					AllowedToChat[targetindex] = true;
					ShowActivity2(client, "[SM] ", "%N has granted %N permission to chat.", client, targetindex);
				}
			}
			else
				ShowActivity2(client, "[SM] ", "%N has granted %s permission to chat.", client, target);
		}
		else
			ReplyToCommand(client, "[SM] You do not have access to that command.");
	}
	else
		ReplyToCommand(client, "[SM] Usage: sm_givechat <@all/@ct/@t/partial name>");
	return Plugin_Handled;
}

public Action:TakeChat(client, args)
{
	if(args > 0)
	{
		if(CheckCommandAccess(client, "sm_limitchat_take", ADMFLAG_GENERIC, true))
		{
			decl String:target[64];
			new targetlist[MAXPLAYERS+1];
			GetCmdArg(1, target, sizeof(target));
			if(FindMatchingPlayers(target, targetlist) == 0)
			{
				new targetindex = FindTarget(client, target);
				if(targetindex > 0)
				{
					AllowedToChat[targetindex] = true;
					ShowActivity2(client, "[SM] ", "%N has denied %N permission to chat.", client, targetindex);
				}
			}
			else
				ShowActivity2(client, "[SM] ", "%N has denied %s permission to chat.", client, target);
		}
		else
			ReplyToCommand(client, "[SM] You do not have access to that command.");
	}
	else
		ReplyToCommand(client, "[SM] Usage: sm_takechat <@all/@ct/@t/partial name>");
	return Plugin_Handled;
}

/***********
 *Callbacks*
************/

public HandleVoteMenu(Handle:menu, MenuAction:action, param1, param2) 
{
	if (action == MenuAction_End) 
		CloseHandle(menu);
	else if (action == MenuAction_VoteEnd)
	{
		decl String:buffer[8];
		GetMenuItem(menu, 0, buffer, sizeof(buffer));
		new client = StringToInt(buffer);
		new admins[MAXPLAYERS+1];
		new count = GetAdminList(admins);
		new votes;
		new totalVotes;
		GetMenuVoteInfo(param2, votes, totalVotes);
		new Float:percent = FloatDiv(float(votes), float(totalVotes));
		if(param1 == 0)
		{
			if(percent < g_cvarNeeded)
			{
				PrintToChat(client, "[SM] You have been denied permission to chat freely.");
				for(new i = 0; i < count; i++)
					PrintToChat(admins[i], "[SM] %N has been denied permission to chat. Received %d\%% of %d votes. (%d%% needed)", client, RoundToNearest(100.0 * percent), totalVotes, RoundToNearest(100.0 * g_cvarNeeded));
			}
			else
			{
				AllowedToChat[client] = true;
				PrintToChat(client, "[SM] You have been granted permission to chat freely.");
				for(new i = 0; i < count; i++)
					PrintToChat(admins[i], "[SM] %N has been granted permission to chat. Received %d\%% of %d votes. (%d%% needed)", client, RoundToNearest(100.0 * percent), totalVotes, RoundToNearest(100.0 * g_cvarNeeded));
			}
		}
		else
		{
			PrintToChat(client, "[SM] You have been denied permission to chat freely.");
			for(new i = 0; i < count; i++)
				PrintToChat(admins[i], "[SM] %N has been denied permission to chat. Received %d\%% of %d votes. (%d%% needed)", client, RoundToNearest(100.0 * (1 - percent)), totalVotes, RoundToNearest(100.0 * g_cvarNeeded));
		}
	}
}

/*********
 *Helpers*
**********/

AllowAdminChat()
{
	new admins[MAXPLAYERS+1];
	new count = GetAdminList(admins);
	for(new i = 0; i < count; i++)
		AllowedToChat[admins[i]] = true;
}

DoVoteMenu(client, const String:reason[])
{
	decl String:buffer[8];
	Format(buffer, sizeof(buffer), "%i", client);
	new Handle:menu = CreateMenu(HandleVoteMenu);
	SetMenuTitle(menu, "%N has requested permission to use chat. Reason: %s", client, reason);
	AddMenuItem(menu, buffer, "Allow");
	AddMenuItem(menu, buffer, "Deny");
	new admins[MAXPLAYERS+1];
	new count = GetAdminList(admins);
	VoteMenu(menu, admins, count, 15);
}

FindMatchingPlayers(const String:matchstr[], clients[])
{
	new k = 0;
	if(StrEqual(matchstr, "@all", false))
	{
		for(new x = 1; x <= MaxClients; x++)
		{
			if(IsClientInGame(x))
			{
				clients[k] = x;
				k++;
			}
		}
	}
	else if(StrEqual(matchstr, "@t", false))
	{
		for(new x = 1; x <= MaxClients; x++)
		{
			if(IsClientInGame(x) && GetClientTeam(x) == 2)
			{
				clients[k] = x;
				k++;
			}
		}
	}
	else if(StrEqual(matchstr, "@ct", false))
	{
		for(new x = 1; x <= MaxClients; x++)
		{
			if(IsClientInGame(x) && GetClientTeam(x) == 3)
			{
				clients[k] = x;
				k++;
			}
		}
	}
	return k;
}

GetAdminList(admins[])
{
	new count = 0;
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && CheckCommandAccess(i, "limitchat", ADMFLAG_GENERIC, true))
		{
			admins[count] = i;
			count++;
		}
	}
	return count;
}

bool:IsValidPhrase(const String:phrase[], startidx=0)
{
	for(new i = 0; i < linecount; i++)
	{
		if(strcmp(phrase[startidx], AllowedPhrases[i], false) == 0)
			return true;
	}
	return false;
}

ReadTextFile()
{
	new Handle:file = OpenFile("addons/sourcemod/configs/allowedchatphrases.txt", "r");
	linecount = 0;
	while(!IsEndOfFile(file))
	{
		ReadFileLine(file, AllowedPhrases[linecount], sizeof(AllowedPhrases[]));
		TrimString(AllowedPhrases[linecount]);
		linecount++;
		PrintToServer("Linecount incremented to: %i", linecount);
	}
}

/*********
 *Convars*
**********/

public ConvarChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if(cvar == h_cvarEnable)
	{
		g_cvarEnable = GetConVarBool(h_cvarEnable);
		if(g_cvarEnable)
		{
			AddCommandListener(OnSayCommand, "say");
			AddCommandListener(OnSayCommand, "say_team");
		}
		else
		{
			RemoveCommandListener(OnSayCommand, "say");
			RemoveCommandListener(OnSayCommand, "say_team");
		}
	}
	else if(cvar == h_cvarAdmins)
	{
		g_cvarAdmins = GetConVarBool(h_cvarAdmins);
		decl admins[MAXPLAYERS+1];
		new count = GetAdminList(admins);
		for(new i = 0; i < count; i++)
			AllowedToChat[admins[i]] = (g_cvarAdmins? true : false);
	}
	else if(cvar == h_cvarRequest)
		g_cvarRequest = GetConVarBool(h_cvarRequest);
	else if(cvar == h_cvarNeeded)
		g_cvarNeeded = GetConVarFloat(h_cvarNeeded);
}

UpdateAllConvars()
{
	g_cvarEnable = GetConVarBool(h_cvarEnable);
	g_cvarAdmins = GetConVarBool(h_cvarAdmins);
	g_cvarRequest = GetConVarBool(h_cvarRequest);
	g_cvarNeeded = GetConVarFloat(h_cvarNeeded);
}