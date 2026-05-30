#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <multicolors>  // 调用 multicolors.inc

#define CVAR_FLAG FCVAR_NOTIFY

enum
{
  TEAM_SPECTATOR = 1,
  TEAM_SURVIVOR,
  TEAM_INFECTED
}

enum
{
  ZC_SMOKER = 1,
  ZC_BOOMER,
  ZC_HUNTER,
  ZC_SPITTER,
  ZC_JOCKEY,
  ZC_CHARGER,
  ZC_WITCH,
  ZC_TANK
}

enum struct PlayerInfo
{
  int  totalDamage;
  int  siCount;
  int  ciCount;
  int  ffCount;
  int  gotFFCount;
  int  headShotCount;

  void init(){
    this.totalDamage = this.siCount = this.ciCount = this.ffCount = this.gotFFCount = this.headShotCount = 0; }
}

PlayerInfo    playerInfos[MAXPLAYERS + 1];

static int    failCount;
static bool   g_bHasPrint;
static bool   g_bHasPrintDetails;
static char   mapName[64];
static Handle g_hAutoBroadcastTimer = null;

public Plugin myinfo =
{
  name        = "Survivor Mvp & Round Status",
  author      = "ExplosionMagic",
  description = "MVP 击杀统计",
  version     = "2026-05-01",
  url         = "https://steamcommunity.com/id/babylon34/"


}

ConVar g_hAllowShowMvp;
ConVar g_hWhichTeamToShow;
ConVar g_hAllowShowInfo;
ConVar g_hAllowShowSi;
ConVar g_hAllowShowCi;
ConVar g_hAllowShowFF;
ConVar g_hAllowShowTotalDmg;
ConVar g_hAllowShowAccuracy;
ConVar g_hAllowShowFailCount;
ConVar g_hAllowShowDetails;
ConVar g_hAllowShowRank;
ConVar g_hAllowShowRankMvp;
ConVar g_hAllowShowRankSI;
ConVar g_hAllowShowRankCI;
ConVar g_hAllowShowRankFF;
ConVar g_hAutoBroadcastInterval;  //自动播报间隔
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  EngineVersion test = GetEngineVersion();
  if (test != Engine_Left4Dead2 && test != Engine_Left4Dead)
  {
    strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
    return APLRes_SilentFailure;
  }
  return APLRes_Success;
}

public void OnPluginStart()
{
  g_hAllowShowMvp          = CreateConVar("mvp_allow_show", "1", "是否启用插件", CVAR_FLAG, true, 0, true, 1);
  g_hWhichTeamToShow       = CreateConVar("mvp_witch_team_show", "0", "允许给哪个团队显示 MVP 信息 (0: 所有团队, 1: 仅旁观者, 2: 仅生还者, 3: 仅特感)", CVAR_FLAG, true, 0.0, true, 3.0);
  g_hAllowShowInfo         = CreateConVar("mvp_allow_show_info", "1", "是否允许显示所有人详细数据", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowSi           = CreateConVar("mvp_allow_show_si", "1", "是否允许显示特感击杀信息", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowCi           = CreateConVar("mvp_allow_show_ci", "1", "是否允许显示丧尸击杀信息", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowFF           = CreateConVar("mvp_allow_show_ff", "1", "是否允许显示友伤信息", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowTotalDmg     = CreateConVar("mvp_allow_show_damage", "1", "是否允许显示总伤害信息", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowAccuracy     = CreateConVar("mvp_allow_show_acc", "1", "是否允许显示爆头信息", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowFailCount    = CreateConVar("mvp_show_fail_count", "1", "是否在团灭时显示团灭次数", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowDetails      = CreateConVar("mvp_show_details", "1", "是否在过关或团灭时显示各项 MVP 数据", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowRank         = CreateConVar("mvp_show_your_rank", "1", "是否允许显示你的排名", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowRankMvp      = CreateConVar("mvp_show_your_rank_mvp", "1", "是否允许在显示各项 MVP 时显示你的排名", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowRankSI       = CreateConVar("mvp_show_your_rank_si", "1", "是否允许显示你的特感排名", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowRankCI       = CreateConVar("mvp_show_your_rank_ci", "1", "是否允许显示你的丧尸排名", CVAR_FLAG, true, 0, true, 1);
  g_hAllowShowRankFF       = CreateConVar("mvp_show_your_rank_ff", "1", "是否允许显示你的友伤排名", CVAR_FLAG, true, 0, true, 1);

  // 自动播报间隔 (单位：秒，0 = 禁用自动播报)
  g_hAutoBroadcastInterval = CreateConVar("mvp_auto_broadcast_interval", "120", "自动播报 MVP 统计的间隔秒数", CVAR_FLAG, true, 0.0, true, 3600.0);

  // Cvar 变动时重启计时器
  g_hAutoBroadcastInterval.AddChangeHook(OnAutoBroadcastIntervalChanged);
  OnAutoBroadcastIntervalChanged(g_hAutoBroadcastInterval, "", "");

  HookEvent("player_death", siDeathHandler);
  HookEvent("infected_death", ciDeathHandler);
  HookEvent("player_hurt", playerHurtHandler);
  HookEvent("round_start", roundStartHandler);
  HookEvent("round_end", roundEndHandler);
  HookEvent("map_transition", roundEndHandler);
  HookEvent("mission_lost", missionLostHandler);
  HookEvent("finale_vehicle_leaving", roundEndHandler);

  RegConsoleCmd("sm_mvp", showMvpHandler);
  RegConsoleCmd("sm_rank", showRankHandler);
}

// Cvar 改变时，自动重启计时器
public void OnAutoBroadcastIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
  if (g_hAutoBroadcastTimer != null)
  {
    KillTimer(g_hAutoBroadcastTimer);
    g_hAutoBroadcastTimer = null;
  }

  float interval = convar.FloatValue;
  if (interval > 0.0)
  {
    g_hAutoBroadcastTimer = CreateTimer(interval, Timer_AutoBroadcast, _, TIMER_REPEAT);
  }
}

// 计时器回调，自动播报当前回合 MVP 信息
public Action Timer_AutoBroadcast(Handle timer)
{
  if (!g_hAllowShowMvp.BoolValue)
    return Plugin_Continue;

  int showTeam = g_hWhichTeamToShow.IntValue;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidClient(i))
      continue;

    // 团队过滤
    if (showTeam != 0 && GetClientTeam(i) != showTeam)
      continue;

    if (g_hAllowShowInfo.BoolValue)
      printMvpStatus(i);
    if (g_hAllowShowDetails.BoolValue)
      printParticularMvp(i);
  }

  return Plugin_Continue;
}

public void OnMapStart()
{
  g_bHasPrint        = false;
  g_bHasPrintDetails = false;

  char nowMapName[64];
  GetCurrentMap(nowMapName, sizeof(nowMapName));
  if (strlen(mapName) < 1 || strcmp(mapName, nowMapName) != 0)
  {
    failCount = 0;
    strcopy(mapName, sizeof(mapName), nowMapName);
  }
  clearStuff();
}

public Action showMvpHandler(int client, int args)
{
  if (!g_hAllowShowMvp.BoolValue)
  {
    ReplyToCommand(client, "[MVP]：当前生还者 MVP 统计数据已禁用");
    return Plugin_Handled;
  }
  if (!IsValidClient(client))
    return Plugin_Handled;

  int team     = GetClientTeam(client);
  int showTeam = g_hWhichTeamToShow.IntValue;
  if (showTeam != 0 && team != showTeam)
  {
    CPrintToChat(client, "{olive}[{default}MVP{olive}]: {default}当前生还者 MVP 统计数据不允许向你所在的团队显示");
    return Plugin_Handled;
  }

  if (g_hAllowShowInfo.BoolValue)
    printMvpStatus(client);
  if (g_hAllowShowDetails.BoolValue)
    printParticularMvp(client);

  return Plugin_Handled;
}

public Action showRankHandler(int client, int args)
{
  if (!g_hAllowShowRank.BoolValue)
  {
    ReplyToCommand(client, "[MVP]：当前生还者排名已禁用");
    return Plugin_Handled;
  }
  showRank(client);
  return Plugin_Handled;
}

public void siDeathHandler(Event event, const char[] name, bool dontBroadcast)
{
  int victim   = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  if (!IsValidClient(victim) || !IsValidClient(attacker) || GetClientTeam(victim) != TEAM_INFECTED || GetClientTeam(attacker) != TEAM_SURVIVOR)
    return;

  int zClass = GetInfectedClass(victim);
  if (zClass < ZC_SMOKER || zClass > ZC_CHARGER)
    return;

  playerInfos[attacker].siCount++;
  if (event.GetBool("headshot"))
    playerInfos[attacker].headShotCount++;
}

public void ciDeathHandler(Event event, const char[] name, bool dontBroadcast)
{
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  if (!IsValidSurvivor(attacker))
    return;

  playerInfos[attacker].ciCount++;
  if (event.GetBool("headshot"))
    playerInfos[attacker].headShotCount++;
}

public void playerHurtHandler(Event event, const char[] name, bool dontBroadcast)
{
  int victim   = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int damage   = event.GetInt("dmg_health");

  if (IsValidSurvivor(attacker) && IsValidSurvivor(victim))
  {
    playerInfos[attacker].ffCount += damage;
    playerInfos[victim].gotFFCount += damage;
  }
  else if (IsValidSurvivor(attacker) && IsValidInfected(victim))
  {
    int zClass = GetInfectedClass(victim);
    if (zClass >= ZC_SMOKER && zClass <= ZC_CHARGER)
      playerInfos[attacker].totalDamage += damage;
  }
}

public void OnClientConnected(int client)
{
  playerInfos[client].init();
}

public void OnClientDisconnect(int client)
{
  playerInfos[client].init();
}

// 自动重启播报计时器
public void roundStartHandler(Event event, const char[] name, bool dontBroadcast)
{
  g_bHasPrint        = false;
  g_bHasPrintDetails = false;

  float interval     = g_hAutoBroadcastInterval.FloatValue;
  if (g_hAutoBroadcastTimer != null)
  {
    KillTimer(g_hAutoBroadcastTimer);
    g_hAutoBroadcastTimer = null;
  }
  if (interval > 0.0)
  {
    g_hAutoBroadcastTimer = CreateTimer(interval, Timer_AutoBroadcast, _, TIMER_REPEAT);
  }

  // 自动清空数据
  char nowMapName[64];
  GetCurrentMap(nowMapName, sizeof(nowMapName));
  if (strlen(mapName) < 1 || strcmp(mapName, nowMapName) != 0)
  {
    failCount = 0;
    strcopy(mapName, sizeof(mapName), nowMapName);
  }
  clearStuff();
}

public void missionLostHandler(Event event, const char[] name, bool dontBroadcast)
{
  if (!g_hAllowShowMvp.BoolValue || g_bHasPrint)
    return;

  // 立即停掉播报计时器，避免回合结束后意外触发
  if (g_hAutoBroadcastTimer != null)
  {
    KillTimer(g_hAutoBroadcastTimer);
    g_hAutoBroadcastTimer = null;
  }

  roundEndPrint();

  if (g_hAllowShowFailCount.BoolValue)
    CPrintToChatAll("{olive}[提示]: {default}这是你们第 {green}%d {default}次团灭，请继续努力哦！(*･ω< )", ++failCount);

  clearStuff();
}

public void roundEndHandler(Event event, const char[] name, bool dontBroadcast)
{
  if (!g_hAllowShowMvp.BoolValue)
    return;

  // 立即停掉播报计时器，避免回合结束后意外触发
  if (g_hAutoBroadcastTimer != null)
  {
    KillTimer(g_hAutoBroadcastTimer);
    g_hAutoBroadcastTimer = null;
  }

  roundEndPrint();
  clearStuff();
}

void clearStuff()
{
  for (int i = 1; i <= MaxClients; i++)
    playerInfos[i].init();
}

/**
 * 回合结束时向允许的团队显示 MVP 信息
 * 确保每个玩家只接收一次，且不会因多次事件重复发送
 */
void roundEndPrint()
{
  bool needInfo    = g_hAllowShowInfo.BoolValue;
  bool needDetails = g_hAllowShowDetails.BoolValue;

  // 如果所有需要显示的内容都已经发送过，直接返回
  if ((needInfo && g_bHasPrint) && (needDetails && g_bHasPrintDetails))
    return;

  int showTeam = g_hWhichTeamToShow.IntValue;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidClient(i))
      continue;

    // 团队过滤：0表示所有团队，否则必须与设定团队一致
    if (showTeam != 0 && GetClientTeam(i) != showTeam)
      continue;

    if (needInfo && !g_bHasPrint)
      printMvpStatus(i);
    if (needDetails && !g_bHasPrintDetails)
    {
      printParticularMvp(i);

      // 显示排名
      // if (g_hAllowShowRank.BoolValue && g_hAllowShowRankMvp.BoolValue)
      //   showRank(i);
    }
  }

  // 标记已发送，避免后续事件重复
  if (needInfo) g_bHasPrint = true;
  if (needDetails) g_bHasPrintDetails = true;
}

/**
 * 显示主 MVP 信息 (特感击杀, 丧尸击杀, 总伤害, 黑枪/被黑, 爆头率)
 * @param client 需要显示的客户端索引
 * @return void
 **/
void printMvpStatus(int client)
{
  int index     = 0;
  int[] players = new int[MaxClients + 1];

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidClient(i) || GetClientTeam(i) != TEAM_SURVIVOR)
      continue;
    players[index++] = i;
  }

  SortCustom1D(players, index, sortByDamageFunction);

  CPrintToChat(client, "{olive}[MVP] {green}击杀统计");

  char buffer[128], toPrint[256];
  for (int i = 0; i < index; i++)
  {
    toPrint[0] = '\0';
    // 特感击杀数
    if (g_hAllowShowSi.BoolValue)
    {
      FormatEx(buffer, sizeof(buffer), "{orange}★ {default}特感:{green}%d ", playerInfos[players[i]].siCount);
      StrCat(toPrint, sizeof(toPrint), buffer);
    }

    // 丧尸击杀数
    if (g_hAllowShowCi.BoolValue)
    {
      FormatEx(buffer, sizeof(buffer), "{default}丧尸:{green}%d ", playerInfos[players[i]].ciCount);
      StrCat(toPrint, sizeof(toPrint), buffer);
    }

    // 总伤害
    if (g_hAllowShowTotalDmg.BoolValue)
    {
      FormatEx(buffer, sizeof(buffer), "{default}伤害:{green}%d ", playerInfos[players[i]].totalDamage);
      StrCat(toPrint, sizeof(toPrint), buffer);
    }

    // 造成友伤/受到友伤
    if (g_hAllowShowFF.BoolValue)
    {
      // 修复：此处必须使用 players[i] 而非 i
      FormatEx(buffer, sizeof(buffer), "{default}友伤:{green}%d ", playerInfos[players[i]].ffCount);
      StrCat(toPrint, sizeof(toPrint), buffer);
      FormatEx(buffer, sizeof(buffer), "{default}被黑:{green}%d ", playerInfos[players[i]].gotFFCount);
      StrCat(toPrint, sizeof(toPrint), buffer);
    }

    // 射击精准度
    //   if (g_hAllowShowAccuracy.BoolValue)
    // {
    //   float accuracy = playerInfos[players[i]].siCount + playerInfos[players[i]].ciCount == 0 ? 0.0 : float(playerInfos[players[i]].headShotCount) / float(playerInfos[players[i]].siCount + playerInfos[players[i]].ciCount);
    //   FormatEx(buffer, sizeof(buffer), "{lightgreen}精准度:{green}%.0f%% ", accuracy * 100.0);
    //   StrCat(toPrint, sizeof(toPrint), buffer);
    // }

    FormatEx(buffer, sizeof(buffer), "{lightgreen}%N", players[i]);
    StrCat(toPrint, sizeof(toPrint), buffer);

    CPrintToChat(client, "%s", toPrint);
  }
}

void printParticularMvp(int client)
{
  int siMvpClient, ciMvpClient, ffMvpClient, gotFFMvpClient;
  int dmgTotal, siTotal, ciTotal, ffTotal, gotFFTotal;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidClient(i) || GetClientTeam(i) != TEAM_SURVIVOR)
      continue;

    dmgTotal += playerInfos[i].totalDamage;
    siTotal += playerInfos[i].siCount;
    ciTotal += playerInfos[i].ciCount;
    ffTotal += playerInfos[i].ffCount;
    gotFFTotal += playerInfos[i].gotFFCount;

    if (playerInfos[i].siCount > playerInfos[siMvpClient].siCount)
      siMvpClient = i;
    if (playerInfos[i].ciCount > playerInfos[ciMvpClient].ciCount)
      ciMvpClient = i;
    if (playerInfos[i].ffCount > playerInfos[ffMvpClient].ffCount)
      ffMvpClient = i;
    if (playerInfos[i].gotFFCount > playerInfos[gotFFMvpClient].gotFFCount)
      gotFFMvpClient = i;
  }

  char clientName[MAX_NAME_LENGTH], buffer[512], temp[256];

  if (g_hAllowShowSi.BoolValue)
  {
    FormatEx(buffer, sizeof(buffer), "{olive}[特感杀手] ");
    if (!IsValidClient(siMvpClient) || siTotal <= 0)
      StrCat(buffer, sizeof(buffer), "{default}本局还没有击杀任何特感");
    else
    {
      formatMvpClientName(siMvpClient, clientName, sizeof(clientName));
      // 避免极端情况百分比除零导致游戏崩溃
      int dmgPercent  = (dmgTotal > 0) ? RoundToNearest(float(playerInfos[siMvpClient].totalDamage) / float(dmgTotal) * 100.0) : 0;
      int killPercent = (siTotal > 0) ? RoundToNearest(float(playerInfos[siMvpClient].siCount) / float(siTotal) * 100.0) : 0;
      FormatEx(temp, sizeof(temp), "%s {default}伤害:{green}%d {default}({green}%d%%{default}), {default}击杀:{green}%d {default}({green}%d%%{default})",
               clientName, playerInfos[siMvpClient].totalDamage, dmgPercent, playerInfos[siMvpClient].siCount, killPercent);
      StrCat(buffer, sizeof(buffer), temp);
    }
    CPrintToChat(client, "%s", buffer);
  }

  if (g_hAllowShowCi.BoolValue)
  {
    FormatEx(buffer, sizeof(buffer), "{olive}[清尸狂人] ");
    if (!IsValidClient(ciMvpClient) || ciTotal <= 0)
      StrCat(buffer, sizeof(buffer), "{default}本局还没有击杀任何丧尸");
    else
    {
      formatMvpClientName(ciMvpClient, clientName, sizeof(clientName));
      int killPercent = (ciTotal > 0) ? RoundToNearest(float(playerInfos[ciMvpClient].ciCount) / float(ciTotal) * 100.0) : 0;
      FormatEx(temp, sizeof(temp), "%s {default}击杀:{green}%d {default}({green}%d%%{default})",
               clientName, playerInfos[ciMvpClient].ciCount, killPercent);
      StrCat(buffer, sizeof(buffer), temp);
    }
    CPrintToChat(client, "%s", buffer);
  }

  if (g_hAllowShowFF.BoolValue)
  {
    // 黑枪最多
    FormatEx(buffer, sizeof(buffer), "{olive}[黑枪之王] ");
    if (!IsValidClient(ffMvpClient) || ffTotal <= 0)
      StrCat(buffer, sizeof(buffer), "{default}大家都没有黑枪");
    else
    {
      formatMvpClientName(ffMvpClient, clientName, sizeof(clientName));
      int killPercent = (ffTotal > 0) ? RoundToNearest(float(playerInfos[ffMvpClient].ffCount) / float(ffTotal) * 100.0) : 0;
      FormatEx(temp, sizeof(temp), "%s {default}造成友伤:{green}%d {default}({green}%d%%{default})",
               clientName, playerInfos[ffMvpClient].ffCount, killPercent);
      StrCat(buffer, sizeof(buffer), temp);
    }
    CPrintToChat(client, "%s", buffer);

    // 挨枪最多
    // FormatEx(buffer, sizeof(buffer), "{olive}[挨枪之王] ");
    // if (!IsValidClient(gotFFMvpClient) || gotFFTotal <= 0)
    //   StrCat(buffer, sizeof(buffer), "{default}暂时没有倒霉蛋被黑得最惨");
    // else
    // {
    //   formatMvpClientName(gotFFMvpClient, clientName, sizeof(clientName));
    //   int killPercent = (gotFFTotal > 0) ? RoundToNearest(float(playerInfos[gotFFMvpClient].gotFFCount) / float(gotFFTotal) * 100.0) : 0;
    //   FormatEx(temp, sizeof(temp), "%s {default}受到友伤:{green}%d {default}({green}%d%%{default})",
    //            clientName, playerInfos[gotFFMvpClient].gotFFCount, killPercent);
    //   StrCat(buffer, sizeof(buffer), temp);
    // }
    // CPrintToChat(client, "%s", buffer);
  }

  // 允许显示排名
  // 移到 roundEndPrint() 实现每回合只打印一次
  // if (g_hAllowShowRank.BoolValue && g_hAllowShowRankMvp.BoolValue)
  // {
  //   showRank(client);
  // }
}

void showRank(int client)
{
  if (!IsValidSurvivor(client))
    return;

  int dmgTotal, siTotal, ciTotal, ffTotal;
  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidClient(i) || GetClientTeam(i) != TEAM_SURVIVOR)
      continue;
    dmgTotal += playerInfos[i].totalDamage;
    siTotal += playerInfos[i].siCount;
    ciTotal += playerInfos[i].ciCount;
    ffTotal += playerInfos[i].ffCount;
  }

  char buffer[128];
  int  rank, dmgPercent, killPercent;  // rank将初始化为0

  // 击杀特感排名
  if (g_hAllowShowSi.BoolValue && g_hAllowShowRankSI.BoolValue)
  {
    rank = GetRank(client, sortBySiCountFunction);
    FormatEx(buffer, sizeof(buffer), "{olive}[特感 RANK]:");
    if (rank > 0 && siTotal > 0)
    {
      if (rank == 1)
        CPrintToChat(client, "%s {default}你是本回合{green}特感杀手", buffer);
      else
      {
        dmgPercent  = (dmgTotal > 0) ? RoundToNearest(float(playerInfos[client].totalDamage) / float(dmgTotal) * 100.0) : 0;
        killPercent = (siTotal > 0) ? RoundToNearest(float(playerInfos[client].siCount) / float(siTotal) * 100.0) : 0;
        CPrintToChat(client, "%s {olive}#%d {default}伤害:{olive}%d {default}({olive}%d%%{default}),{default}击杀:{olive}%d {default}({olive}%d%%{default})",
                     buffer, rank, playerInfos[client].totalDamage, dmgPercent, playerInfos[client].siCount, killPercent);
      }
    }
    else
      CPrintToChat(client, "%s {default}暂无排名", buffer);
  }

  // 击杀丧尸排名
  if (g_hAllowShowCi.BoolValue && g_hAllowShowRankCI.BoolValue)
  {
    rank = GetRank(client, sortByCiCountFunction);
    FormatEx(buffer, sizeof(buffer), "{olive}[丧尸 RANK]:");
    if (rank > 0 && ciTotal > 0)
    {
      if (rank == 1)
        CPrintToChat(client, "%s {default}你是本回合{green}清尸狂人", buffer);
      else
      {
        killPercent = (ciTotal > 0) ? RoundToNearest(float(playerInfos[client].ciCount) / float(ciTotal) * 100.0) : 0;
        CPrintToChat(client, "%s {green}#%d {default}击杀:{olive}%d {default}({olive}%d%%{default})",
                     buffer, rank, playerInfos[client].ciCount, killPercent);
      }
    }
    else
      CPrintToChat(client, "%s {default}暂无排名", buffer);
  }

  // 造成友伤排名
  if (g_hAllowShowFF.BoolValue && g_hAllowShowRankFF.BoolValue)
  {
    rank = GetRank(client, sortByFriendlyFireFunction);
    FormatEx(buffer, sizeof(buffer), "{olive}[友伤 RANK]:");
    if (rank > 0 && ffTotal > 0)
    {
      if (rank == 1)
        CPrintToChat(client, "%s {default}你是本回合{green}黑枪之王", buffer);
      else
      {
        killPercent = (ffTotal > 0) ? RoundToNearest(float(playerInfos[client].ffCount) / float(ffTotal) * 100.0) : 0;
        CPrintToChat(client, "%s {green}#%d {default}造成友伤:{olive}%d {default}({olive}%d%%{default})",
                     buffer, rank, playerInfos[client].ffCount, killPercent);
      }
    }
    else
      CPrintToChat(client, "%s {default}暂无排名", buffer);
  }
}

int GetRank(int client, SortFunc1D SortRank)
{
  int index     = 0;
  int[] players = new int[MaxClients + 1];
  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsValidSurvivor(i))
      continue;
    players[index++] = i;
  }

  SortCustom1D(players, index, SortRank);

  int rank = 0;  // rank初始化为0，表示未找到
  for (int i = 0; i < index; i++)
  {
    if (players[i] == client)
    {
      rank = i + 1;
      break;
    }
  }
  return rank;
}

/**
 * 根据客户端是否为 BOT 在其名字后面添加 [BOT] 字样
 * @param client 需要获取名称的客户端索引
 * @param str 名称字符串
 * @param len 字符串长度
 * @return void
 **/
void formatMvpClientName(int client, char[] str, int len)
{
  if (IsFakeClient(client))
    FormatEx(str, len, "{lightgreen}[BOT] %N", client);
  else
    FormatEx(str, len, "{lightgreen}%N", client);
}

// ============ 排序函数 ============
/**
 * 按照生还者总伤害击杀特感数量 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortBySiCountFunction(int x, int y, const int[] array, Handle hndl)
{
  return playerInfos[x].siCount > playerInfos[y].siCount ? -1 : (playerInfos[x].siCount == playerInfos[y].siCount ? 0 : 1);
}

/**
 * 按照生还者击杀丧尸数量 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortByCiCountFunction(int x, int y, const int[] array, Handle hndl)
{
  if (playerInfos[x].ciCount > playerInfos[y].ciCount)
    return -1;
  if (playerInfos[x].ciCount == playerInfos[y].ciCount)
    return x > y ? -1 : 1;
  return 1;
}

/**
 * 按照生还者总伤害 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortByTotalDamageFunction(int x, int y, const int[] array, Handle hndl)
{
  if (playerInfos[x].totalDamage > playerInfos[y].totalDamage)
    return -1;
  if (playerInfos[x].totalDamage == playerInfos[y].totalDamage)
    return x > y ? -1 : 1;
  return 1;
}

/**
 * 按照生还者总伤害 -> 射击精准度 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortByDamageFunction(int x, int y, const int[] array, Handle hndl)
{
  int xDamage = playerInfos[x].totalDamage;
  int yDamage = playerInfos[y].totalDamage;

  if (xDamage > yDamage) return -1;
  if (xDamage < yDamage) return 1;

  // 伤害相同，比射击精准度
  int   xCount = playerInfos[x].siCount + playerInfos[x].ciCount;
  int   yCount = playerInfos[y].siCount + playerInfos[y].ciCount;
  float xAcc   = (xCount > 0) ? float(playerInfos[x].headShotCount) / float(xCount) : 0.0;
  float yAcc   = (yCount > 0) ? float(playerInfos[y].headShotCount) / float(yCount) : 0.0;

  if (xAcc > yAcc) return -1;
  if (xAcc < yAcc) return 1;
  // 若射击精准度相同，按客户端索引（较小的在前）
  return x > y ? -1 : 1;
}

/**
 * 按照生还者黑枪 -> 被黑 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortByFriendlyFireFunction(int x, int y, const int[] array, Handle hndl)
{
  if (playerInfos[x].ffCount > playerInfos[y].ffCount)
    return -1;
  if (playerInfos[x].ffCount == playerInfos[y].ffCount)
  {
    if (playerInfos[x].gotFFCount > playerInfos[y].gotFFCount)
      return -1;
    if (playerInfos[x].gotFFCount == playerInfos[y].gotFFCount)
      return x > y ? -1 : 1;
  }
  return 1;
}

/**
 * 按照生还者被黑 -> 客户端索引排序
 * @param x 第一个参与排序的元素
 * @param y 第二个参与排序的元素
 * @param array 原数组
 * @param hndl 可选句柄
 * @return int
 **/
stock int sortByFFReceiveFunction(int x, int y, const int[] array, Handle hndl)
{
  if (playerInfos[x].gotFFCount > playerInfos[y].gotFFCount)
    return -1;
  if (playerInfos[x].gotFFCount == playerInfos[y].gotFFCount)
    return x > y ? -1 : 1;
  return 1;
}

// ============ 工具函数 ============
// 判断是否有效玩家 id，有效返回 true，无效返回 false
// @client：需要判断的生还者客户端索引
stock bool IsValidClient(int client)
{
  return client > 0 && client <= MaxClients && IsClientInGame(client);
}

// 判断生还者是否有效，有效返回 true，无效返回 false
// @client：需要判断的生还者客户端索引
stock bool IsValidSurvivor(int client)
{
  return IsValidClient(client) && GetClientTeam(client) == view_as<int>(TEAM_SURVIVOR);
}

// 判断特感是否有效，有效返回 true，无效返回 false
stock bool IsValidInfected(int client)
{
  return IsValidClient(client) && GetClientTeam(client) == TEAM_INFECTED;
}

// 获取特感类型，成功返回特感类型，失败返回 -1
stock int GetInfectedClass(int client)
{
  return IsValidInfected(client) ? GetEntProp(client, Prop_Send, "m_zombieClass") : -1;
}