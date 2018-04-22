/******************************************************************/
/*                                                                */
/*                          AFK Manager                           */
/*                                                                */
/*                                                                */
/*  File:          AFKManager.sp                                  */
/*  Description:   Kick or Move player if AFK.                    */
/*                                                                */
/*                                                                */
/*  Copyright (C) 2018  Kyle                                      */
/*  2018/04/22 13:14:00                                           */
/*                                                                */
/*  This code is licensed under the GPLv3 License.                  */
/*                                                                */
/******************************************************************/


#pragma semicolon 1
#pragma newdecls required

#include <smutils>

#define PI_NAME "AFK Manager"
#define PI_AUTH "Kyle"
#define PI_DESC "Kick or Move player if AFK."
#define PI_VERS "1.0"
#define PI_URLS "https://kxnrl.com"

public Plugin myinfo = 
{
    name        = PI_NAME,
    author      = PI_AUTH,
    description = PI_DESC,
    version     = PI_VERS,
    url         = PI_URLS
};

float g_fClientAgl[MAXPLAYERS+1][3];
float g_fClientPos[MAXPLAYERS+1][3];

int g_iClientTick[MAXPLAYERS+1];
int g_iSpecTarget[MAXPLAYERS+1];

bool g_bIgnorePos[MAXPLAYERS+1];
bool g_bIgnoreAgl[MAXPLAYERS+1];
bool g_bIgnoreObs[MAXPLAYERS+1];

static void SetPlayerDefault(int client, bool fullyReset = false)
{
    g_bIgnorePos[client] = false;
    g_bIgnoreAgl[client] = false;
    g_bIgnoreObs[client] = false;
    
    g_iClientTick[client] = 0;

    if(fullyReset)
    {
        for(int i = 0; i < 3; ++i)
        {
            g_fClientAgl[client][i] = 0.0;
            g_fClientPos[client][i] = 0.0;
        }
    }
}

public void OnPluginStart()
{
    CreateTimer(1.0, Timer_Check, _, TIMER_REPEAT);

    HookEntityOutput("trigger_teleport", "OnEndTouch", Event_PlayerTeleported);

    FindConVar("mp_spectators_max").IntValue = MaxClients - 1;
    
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_hurt",  Event_PlayerHurt,  EventHookMode_Post);
    
    AddCommandListener(Command_Listener, "jointeam");
    AddCommandListener(Command_Listener, "+lookatweapon");
}

// _voiceannounceex_included_
public void OnClientSpeakingEnd(int client)
{
    SetPlayerDefault(client);
}

// _zombiereloaded_included_
public void ZR_OnClientInfected(int client)
{
    if(!ClientIsValid(client))
        return;

    SetPlayerDefault(client);
}

// _ttt_included_
public void TTT_OnItemPurchased(int client, const char[] item)
{
    SetPlayerDefault(client);
}

// _warden_included
public void warden_OnWardenCreatedByUser(int client)
{
    SetPlayerDefault(client);
}

// _LastRequest_Included_
public void OnStartLR(int client, int target, int LR_Type)
{
    SetPlayerDefault(client);
    SetPlayerDefault(target);
}

public void OnClientConnected(int client)
{
	SetPlayerDefault(client, true);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    g_bIgnoreAgl[client] = true;
    g_bIgnorePos[client] = true;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    g_bIgnoreObs[GetClientOfUserId(event.GetInt("userid"))] = true;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    SetPlayerDefault(GetClientOfUserId(event.GetInt("attacker")));
}

public void Event_PlayerTeleported(const char[] output, int caller, int client, float delay)
{
    if(!ClientIsAlive(client))
        return;
    
    g_bIgnoreAgl[client] = true;
    g_bIgnorePos[client] = true;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if(!client)
        return;

    SetPlayerDefault(client);
}

public Action Command_Listener(int client, const char[] command, int argc)
{
    if(ClientIsValid(client))
        SetPlayerDefault(client);

    return Plugin_Continue;
}

public Action Timer_Check(Handle timer)
{
    for(int client = 1; client <= MaxClients; ++client)
    {
        if(!IsClientInGame(client) || IsFakeClient(client))
            continue;

        CheckTick(client);

        if(IsClientObserver(client) && !CheckSpec(client))
            continue;

        if(!CheckPosAgl(client))
            continue;

        SetPlayerDefault(client);
    }
    
    return Plugin_Continue;
}

static void CheckTick(int client)
{
    int team = GetClientTeam(client);

    if(team == 0)
    {
        if(g_iClientTick[client] >= 30)
        {
            LogEx(client, "Kick from non-team");
            KickClient(client, "[AFK Manager]  您因为挂机被踢出游戏.");
        }
    }
    else if(team == 1)
    {
        if(g_iClientTick[client] >= 300)
        {
            LogEx(client, "Kick from Specator");
            KickClient(client, "[AFK Manager]  您因为挂机被踢出游戏.");
        }
        else if(g_iClientTick[client] >= 240)
            Text(client, "<font size='28' color='#0000ff' face='consolas'>[AFK]</font>  <font size='22' color='#00ff00'>您还有</font> <font size='28' color='#ff0000' face='consolas'>%02d秒</font> <font size='22' color='#00ff00'>就要被移除出游戏.", 300 - g_iClientTick[client]); 
    }
    else
    {
        if(g_iClientTick[client] >= 90)
        {
            ChangeClientTeam(client, 1);
            LogEx(client, "Move to Specator from %s", team == 2 ? "TE" : "CT");
        }
        else if(g_iClientTick[client] >= 60)
            Text(client, "<font size='28' color='#0000ff' face='consolas'>[AFK]</font>  <font size='22' color='#00ff00' >您还有</font> <font size='28' color='#ff0000' face='consolas'>%02d秒</font> <font size='22' color='#00ff00'>就要被移动到观察者.", 90 - g_iClientTick[client]); 
    }

    g_iClientTick[client]++;
}

static bool CheckSpec(int client)
{
    bool bypass = true;

    if(g_bIgnoreObs[client])
    {
        g_bIgnoreObs [client] = false;
        g_iSpecTarget[client] = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        return bypass;
    }

    int m_iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

    if(!(4 <= m_iObserverMode <= 5))
        return bypass;

    int m_hObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

    if(g_iSpecTarget[client] != m_hObserverTarget)
    {
        if(ClientIsAlive(g_iSpecTarget[client]))
            bypass = true;

        g_iSpecTarget[client] = m_hObserverTarget;
    }

    return bypass;
}

static bool CheckPosAgl(int client)
{
    bool bypass = false;

    float m_fAgl[3];
    GetClientEyeAngles(client, m_fAgl);
    if(!g_bIgnoreAgl[client])
    {
        if(m_fAgl[0] != 0.0 && g_fClientAgl[client][0] != m_fAgl[0])
            bypass = true;
    }
    else
        g_bIgnoreAgl[client] = false;

    float m_fPos[3];
    GetClientAbsOrigin(client, m_fPos);
    if(!g_bIgnorePos[client])
    {
        float m_fDistance = GetVectorDistance(m_fPos, g_fClientPos[client]);
        if(m_fDistance >= 26.0 && !(125.0 <= m_fDistance <= 135.0))
            bypass = true;
    }
    else
        g_bIgnorePos[client] = false;

    g_fClientPos[client] = m_fPos;
    g_fClientAgl[client] = m_fAgl;

    return bypass;
}

stock void LogEx(int client, const char[] buffer, any ...)
{
    char logMessage[512];
    VFormat(logMessage, 512, buffer, 3);
    LogToFileEx("addons/sourcemod/logs/afk.log", "\"%L\"  -> Tick: %d  -> %s", client, g_iClientTick[client], logMessage);
}
