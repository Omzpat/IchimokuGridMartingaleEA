//+------------------------------------------------------------------+
//|                               EA_Ichimoku_Martingale_Grid.mq5    |
//|                     Grid Martingale piloté par Ichimoku          |
//|                     Version sans sécurité (risque de ruine)      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025 - Ichimoku Grid Martingale"
#property link      ""
#property version   "1.00"

//--- Paramètres de trading (martingale)
input double   InpInitialLot       = 0.01;      // Lot de départ
input double   InpMultiplier       = 2.0;       // Multiplicateur de lot (martingale)
input int      InpGridStepPoints   = 800;       // Écart entre ordres (points)
input double   InpGlobalTakeProfit = 10.0;      // Take Profit global en $ (somme des positions)
input ulong    InpMagicNumber      = 202504;    // Magic Number

//--- Paramètres Ichimoku
input int      InpTenkan           = 9;         // Période Tenkan-sen
input int      InpKijun            = 26;        // Période Kijun-sen
input int      InpSenkou           = 52;        // Période Senkou Span B
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Timeframe pour Ichimoku

//--- Options de direction
input bool     InpAllowBuy         = true;      // Autoriser les achats
input bool     InpAllowSell        = true;      // Autoriser les ventes

//--- Variables globales
double   lastUsedLot       = 0.0;               // Dernier lot utilisé
int      hIchimoku         = INVALID_HANDLE;    // Handle Ichimoku
ENUM_ORDER_TYPE_FILLING  supportedFilling = ORDER_FILLING_FOK;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Détection du mode d'exécution des ordres
   if(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE) & SYMBOL_FILLING_FOK)
      supportedFilling = ORDER_FILLING_FOK;
   else if(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE) & SYMBOL_FILLING_IOC)
      supportedFilling = ORDER_FILLING_IOC;
   else
      supportedFilling = ORDER_FILLING_RETURN;

   // Création du handle Ichimoku
   hIchimoku = iIchimoku(_Symbol, InpTimeframe, InpTenkan, InpKijun, InpSenkou);
   if(hIchimoku == INVALID_HANDLE)
   {
      Print("Erreur création Ichimoku: ", GetLastError());
      return(INIT_FAILED);
   }

   Print("========================================");
   Print("EA Martingale Ichimoku initialisé.");
   Print("Tenkan=", InpTenkan, " Kijun=", InpKijun, " Senkou=", InpSenkou);
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Filling mode: ", EnumToString(supportedFilling));
   Print("ATTENTION : Aucune sécurité. Risque de ruine totale.");
   Print("========================================");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   int posCount = CountPositions();

   // --- Aucune position : vérifier le signal Ichimoku ---
   if(posCount == 0)
   {
      int trend = GetIchimokuTrend();
      bool signalBuy  = false;
      bool signalSell = false;

      if(trend == 1)  // Tendance haussière
         signalBuy = IsTenkanCrossAboveKijun();
      else if(trend == -1) // Tendance baissière
         signalSell = IsTenkanCrossBelowKijun();

      if(signalBuy && InpAllowBuy)
         OpenNewTrade(ORDER_TYPE_BUY);
      else if(signalSell && InpAllowSell)
         OpenNewTrade(ORDER_TYPE_SELL);
   }
   else
   {
      // --- Gestion de la martingale pour le panier existant ---
      int currentDir = GetCurrentDirection();
      if(currentDir == 1)
         ManageMartingale(ORDER_TYPE_BUY);
      else if(currentDir == -1)
         ManageMartingale(ORDER_TYPE_SELL);

      // --- Vérification du Take Profit global ---
      CheckGlobalTakeProfit();
   }
}

//+------------------------------------------------------------------+
//| Retourne la tendance basée sur le nuage Ichimoku                 |
//|  1 = prix > nuage (haussière)                                    |
//| -1 = prix < nuage (baissière)                                    |
//|  0 = prix dans le nuage                                          |
//+------------------------------------------------------------------+
int GetIchimokuTrend()
{
   double senkouA[1], senkouB[1];
   if(CopyBuffer(hIchimoku, 2, 1, 1, senkouA) <= 0) return 0;
   if(CopyBuffer(hIchimoku, 3, 1, 1, senkouB) <= 0) return 0;

   double cloudTop    = MathMax(senkouA[0], senkouB[0]);
   double cloudBottom = MathMin(senkouA[0], senkouB[0]);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(currentPrice > cloudTop)       return 1;
   else if(currentPrice < cloudBottom) return -1;
   else                               return 0;
}

//+------------------------------------------------------------------+
//| Vérifie si Tenkan-sen croise au-dessus de Kijun-sen              |
//+------------------------------------------------------------------+
bool IsTenkanCrossAboveKijun()
{
   double tenkan[2], kijun[2];
   if(CopyBuffer(hIchimoku, 0, 1, 2, tenkan) <= 0) return false;
   if(CopyBuffer(hIchimoku, 1, 1, 2, kijun) <= 0) return false;

   // Croisement haussier : précédente barre Tenkan <= Kijun, actuelle Tenkan > Kijun
   return (tenkan[1] <= kijun[1] && tenkan[0] > kijun[0]);
}

//+------------------------------------------------------------------+
//| Vérifie si Tenkan-sen croise en-dessous de Kijun-sen             |
//+------------------------------------------------------------------+
bool IsTenkanCrossBelowKijun()
{
   double tenkan[2], kijun[2];
   if(CopyBuffer(hIchimoku, 0, 1, 2, tenkan) <= 0) return false;
   if(CopyBuffer(hIchimoku, 1, 1, 2, kijun) <= 0) return false;

   // Croisement baissier : précédente barre Tenkan >= Kijun, actuelle Tenkan < Kijun
   return (tenkan[1] >= kijun[1] && tenkan[0] < kijun[0]);
}

//+------------------------------------------------------------------+
//| Retourne la direction du panier existant (1 = buy, -1 = sell)    |
//+------------------------------------------------------------------+
int GetCurrentDirection()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) return 1;
            else return -1;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Gestion de la grille martingale (identique au bot Ichimoku)      |
//+------------------------------------------------------------------+
void ManageMartingale(ENUM_ORDER_TYPE orderType)
{
   if(CountPositions() == 0) return;

   double extremePrice = (orderType == ORDER_TYPE_BUY) ? DBL_MAX : -DBL_MAX;
   double lastLot = 0.0;

   // Trouver le prix extrême et le dernier lot utilisé
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(orderType == ORDER_TYPE_BUY)
            {
               if(openPrice < extremePrice) extremePrice = openPrice;
            }
            else
            {
               if(openPrice > extremePrice) extremePrice = openPrice;
            }
            lastLot = PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   if(lastLot != 0) lastUsedLot = lastLot;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double step = InpGridStepPoints * _Point;

   bool addOrder = false;
   if(orderType == ORDER_TYPE_BUY && currentPrice <= extremePrice - step)
      addOrder = true;
   else if(orderType == ORDER_TYPE_SELL && currentPrice >= extremePrice + step)
      addOrder = true;

   if(addOrder)
      OpenNewTrade(orderType);
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre (premier ou suivant)                        |
//+------------------------------------------------------------------+
void OpenNewTrade(ENUM_ORDER_TYPE type)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lotSize = (lastUsedLot == 0) ? InpInitialLot : NormalizeDouble(lastUsedLot * InpMultiplier, 2);

   // Respecter les limites du broker
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathMax(minLot, lotSize);
   lotSize = MathMin(maxLot, lotSize);
   lotSize = NormalizeDouble(MathRound(lotSize / lotStep) * lotStep, 2);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = lotSize;
   request.type         = type;
   request.price        = price;
   request.deviation    = 50;
   request.magic        = InpMagicNumber;
   request.type_filling = supportedFilling;
   request.comment      = (type == ORDER_TYPE_BUY) ? "Ichi Buy" : "Ichi Sell";

   if(!OrderSend(request, result))
   {
      Print("Erreur ouverture: ", result.retcode);
      return;
   }

   if(result.retcode == TRADE_RETCODE_DONE)
   {
      lastUsedLot = lotSize;
      Print("Ordre ouvert: ", EnumToString(type), " Lot=", lotSize,
            " Prix=", result.price, " Total positions=", CountPositions());
   }
}

//+------------------------------------------------------------------+
//| Compte les positions de l'EA                                     |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Vérifie et ferme le panier si Take Profit global atteint         |
//+------------------------------------------------------------------+
void CheckGlobalTakeProfit()
{
   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            totalProfit += PositionGetDouble(POSITION_PROFIT);
   }

   if(totalProfit >= InpGlobalTakeProfit)
   {
      Print("Take Profit global atteint: ", totalProfit, " $. Fermeture de tout le panier.");
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Ferme toutes les positions du panier                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};
            request.action    = TRADE_ACTION_DEAL;
            request.symbol    = _Symbol;
            request.volume    = PositionGetDouble(POSITION_VOLUME);
            request.type      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position  = ticket;
            request.price     = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 50;
            request.magic     = InpMagicNumber;
            request.type_filling = supportedFilling;
            if(!OrderSend(request, result))
               Print("Erreur fermeture ", ticket, ": ", result.retcode);
         }
      }
   }
   lastUsedLot = 0.0;
}

//+------------------------------------------------------------------+
//| Nettoyage                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hIchimoku != INVALID_HANDLE)
      IndicatorRelease(hIchimoku);
   Print("EA désinitialisé.");
}
//+------------------------------------------------------------------+