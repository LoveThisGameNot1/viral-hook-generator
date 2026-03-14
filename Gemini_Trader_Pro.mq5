//+------------------------------------------------------------------+
//| Gemini_Trader_Pro.mq5                                            |
//| Copyright 2026, OpenClaw AI                                      |
//+------------------------------------------------------------------+
#property copyright "OpenClaw AI"
#property link "https://openclaw.ai"
#property version "1.20" 

#include <Trade\Trade.mqh>
CTrade trade;

input string InpSymbols = "BTCUSD,ETHUSD,EURUSD"; 
input ENUM_TIMEFRAMES InpTimeFrame = PERIOD_H1; 
input double RiskPercent = 1.0; 

input double SL_Multiplier = 3.0; 
input double TP_Multiplier = 6.0; 

input int Max_Spread_Points = 30;         
input int Forex_Start_Hour_GMT = 7;       
input int Forex_End_Hour_GMT = 17;        

input bool Use_Partial_Close = true;      
input bool Use_Trailing_Stop = true;      
input double Trailing_Stop_Mult = 2.0;    

string gemini_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:generateContent?key=";
string symbol_array[];
ulong partial_closed_tickets[]; 

string GetHiddenKey()
 {
 string p1 = "AIzaSyBjCf";
 string p2 = "bqOMvQM6F3a";
 string p3 = "I5vyZpE71LP";
 string p4 = "nybqMHo";
 return p1 + p2 + p3 + p4;
 }

string DrawBar(int value)
 {
 int filled = (int)MathRound(value / 5.0); 
 if(filled > 20) filled = 20;
 if(filled < 0) filled = 0;
 string bar = "[";
 for(int i=0; i<filled; i++) bar += "#";
 for(int i=filled; i<20; i++) bar += "-";
 bar += "] " + IntegerToString(value) + "%";
 return bar;
 }

int OnInit()
 {
 string temp_symbols = InpSymbols;
 StringReplace(temp_symbols, " ", ""); 
 StringSplit(temp_symbols, ',', symbol_array);
 
 if(ArraySize(symbol_array) == 0) return(INIT_FAILED);
 
 for(int i=0; i<ArraySize(symbol_array); i++)
 {
 SymbolSelect(symbol_array[i], true); 
 }
 return(INIT_SUCCEEDED);
 }

bool IsTicketPartiallyClosed(ulong ticket)
 {
 for(int i=0; i<ArraySize(partial_closed_tickets); i++)
   if(partial_closed_tickets[i] == ticket) return true;
 return false;
 }

void AddTicketToPartialClosed(ulong ticket)
 {
 int size = ArraySize(partial_closed_tickets);
 ArrayResize(partial_closed_tickets, size + 1);
 partial_closed_tickets[size] = ticket;
 }

void ManageRunningTrades()
 {
 for(int i = PositionsTotal() - 1; i >= 0; i--)
 {
 ulong ticket = PositionGetTicket(i);
 if(ticket <= 0) continue;

 string sym = PositionGetString(POSITION_SYMBOL);
 bool is_portfolio = false;
 for(int j=0; j<ArraySize(symbol_array); j++) { if(sym == symbol_array[j]) is_portfolio = true; }
 if(!is_portfolio) continue;

 double point = SymbolInfoDouble(sym, SYMBOL_POINT);
 long spread_points = SymbolInfoInteger(sym, SYMBOL_SPREAD);
 if(spread_points <= 0) spread_points = 20; 

 double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
 double current_sl = PositionGetDouble(POSITION_SL);
 double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
 double volume = PositionGetDouble(POSITION_VOLUME);
 long type = PositionGetInteger(POSITION_TYPE);
 
 double one_r_distance = (spread_points * SL_Multiplier) * point; 
 double trail_distance = (spread_points * Trailing_Stop_Mult) * point; 
 
 if(Use_Partial_Close && !IsTicketPartiallyClosed(ticket))
 {
    if(type == POSITION_TYPE_BUY && (current_price - open_price) >= one_r_distance)
    {
       double half_vol = volume / 2.0;
       double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
       if(half_vol >= min_lot) 
       {
          trade.PositionClosePartial(ticket, half_vol);
          AddTicketToPartialClosed(ticket);
          Print(">>> PARTIAL CLOSE BUY ", sym, " | 50% Profit gesichert.");
       }
    }
    else if(type == POSITION_TYPE_SELL && (open_price - current_price) >= one_r_distance)
    {
       double half_vol = volume / 2.0;
       double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
       if(half_vol >= min_lot) 
       {
          trade.PositionClosePartial(ticket, half_vol);
          AddTicketToPartialClosed(ticket);
          Print(">>> PARTIAL CLOSE SELL ", sym, " | 50% Profit gesichert.");
       }
    }
 }

 if(Use_Trailing_Stop)
 {
    if(type == POSITION_TYPE_BUY)
    {
       double new_sl = current_price - trail_distance;
       if(new_sl > current_sl && new_sl > open_price) 
       {
          trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
       }
    }
    else if(type == POSITION_TYPE_SELL)
    {
       double new_sl = current_price + trail_distance;
       if((current_sl == 0 || new_sl < current_sl) && new_sl < open_price)
       {
          trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
       }
    }
 }
 }
 }

void OnTick()
 {
 ManageRunningTrades(); 
 
 static datetime last_time = 0;
 datetime time_array[];
 if(CopyTime(_Symbol, InpTimeFrame, 0, 1, time_array) <= 0) return;
 
 if(time_array[0] == last_time) return;
 last_time = time_array[0]; 
 
 string tf_name = EnumToString(InpTimeFrame);
 StringReplace(tf_name, "PERIOD_", "");
 
 string prompt = "System-Prompt: Analysiere im " + tf_name + " Chart: 1. RSI/MACD Divergenzen 2. Liquidity Sweeps 3. Orderbuch-Imbalance. Werte Spreads und OHLC aus:\n\n";
 int active_symbols = 0; 
 
 MqlDateTime gmt_time;
 TimeGMT(gmt_time); 
 bool is_forex_session = (gmt_time.hour >= Forex_Start_Hour_GMT && gmt_time.hour < Forex_End_Hour_GMT);
 bool is_weekend = (gmt_time.day_of_week == 0 || gmt_time.day_of_week == 6);
 
 for(int i=0; i<ArraySize(symbol_array); i++)
 {
 string sym = symbol_array[i];
 bool is_crypto = (StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 || StringFind(sym, "SOL") >= 0 || StringFind(sym, "XRP") >= 0 || StringFind(sym, "DOGE") >= 0);
 
 bool has_position = false;
 for(int p=0; p<PositionsTotal(); p++) {
    if(PositionGetTicket(p) > 0 && PositionGetString(POSITION_SYMBOL) == sym) { has_position = true; break; }
 }
 if(has_position) continue; 
 
 if(!is_crypto)
 {
    if(is_weekend) continue; 
    if(!is_forex_session) continue; 
    
    long spread_points = SymbolInfoInteger(sym, SYMBOL_SPREAD);
    if(spread_points > Max_Spread_Points)
    {
       Print(">>> SPREAD ZU HOCH: ", sym, " (", spread_points, ") | Analyse wird ignoriert.");
       continue;
    }
 }
 
 long spread_points = SymbolInfoInteger(sym, SYMBOL_SPREAD);
 double open[], high[], low[], close[];
 if(CopyOpen(sym, InpTimeFrame, 1, 5, open) <= 0) continue;
 if(CopyHigh(sym, InpTimeFrame, 1, 5, high) <= 0) continue;
 if(CopyLow(sym, InpTimeFrame, 1, 5, low) <= 0) continue;
 if(CopyClose(sym, InpTimeFrame, 1, 5, close) <= 0) continue;
 
 string price_data = "";
 for(int k=0; k<5; k++)
 {
 price_data += "K" + IntegerToString(k+1) + ": O=" + DoubleToString(open[k], 5) + 
 " H=" + DoubleToString(high[k], 5) + " L=" + DoubleToString(low[k], 5) + 
 " C=" + DoubleToString(close[k], 5) + " | ";
 }
 prompt += sym + " | SPREAD:" + IntegerToString(spread_points) + " | DATEN: " + price_data + "\n";
 active_symbols++;
 }
 
 if(active_symbols == 0) return; 
 
 prompt += "\nAntworte NUR in diesem extrem kurzen Format (um API-Tokens zu sparen). Keine Erklaerungen!\n";
 prompt += "Format: SYMBOL:ACTION:BULLISH_PROZENT:BEARISH_PROZENT:CONFIDENCE_PROZENT;\n";

 string json_payload = "{\"contents\":[{\"parts\":[{\"text\":\"" + prompt + "\"}]}]}";
 char post[], result[];
 string result_headers;
 StringToCharArray(json_payload, post, 0, WHOLE_ARRAY, CP_UTF8);
 ArrayResize(post, ArraySize(post) - 1); 
 
 string headers = "Content-Type: application/json\r\n";
 string full_url = gemini_url + GetHiddenKey();
 
 int res = WebRequest("POST", full_url, headers, 10000, post, result, result_headers);
 
 if(res == 200)
 {
 string response = CharArrayToString(result);
 
 int start_idx = StringFind(response, "\"text\":");
 if(start_idx >= 0) {
     start_idx = StringFind(response, "\"", start_idx + 7);
     if(start_idx >= 0) {
         int end_idx = StringFind(response, "\"", start_idx + 1);
         if(end_idx >= 0) {
             response = StringSubstr(response, start_idx + 1, end_idx - start_idx - 1);
         }
     }
 }
 StringReplace(response, "\\n", ""); 
 StringReplace(response, " ", ""); 
 
 string pairs[];
 int pair_count = StringSplit(response, ';', pairs);
 
 for(int i=0; i<pair_count; i++)
 {
    string data[];
    if(StringSplit(pairs[i], ':', data) >= 5)
    {
       string sym = data[0];
       string signal = data[1];
       int bullish = (int)StringToInteger(data[2]);
       int bearish = (int)StringToInteger(data[3]);
       int conf = (int)StringToInteger(data[4]);
       
       Print("--- GEMINI 3.1 PRO | ", sym, " ---");
       Print("Bullish Momentum : ", DrawBar(bullish));
       Print("Bearish Pressure : ", DrawBar(bearish));
       Print("Trade Confidence : ", DrawBar(conf));
       Print("AI DECISION      : ", signal);
       Print("-----------------------------------");
       
       bool is_my_symbol = false;
       for(int s=0; s<ArraySize(symbol_array); s++) { if(sym == symbol_array[s]) is_my_symbol = true; }
       if(!is_my_symbol) continue;
       
       if(signal == "HOLD") continue;
       
       double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
       double bid = SymbolInfoDouble(sym, SYMBOL_BID);
       double point = SymbolInfoDouble(sym, SYMBOL_POINT);
       long spread_points = SymbolInfoInteger(sym, SYMBOL_SPREAD);
       if(spread_points <= 0) spread_points = 20;
       
       long stop_level = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
       double sl_dist = (spread_points * SL_Multiplier) * point;
       double tp_dist = (spread_points * TP_Multiplier) * point;
       
       double min_dist = (stop_level + spread_points) * point;
       if(sl_dist < min_dist) sl_dist = min_dist;
       if(tp_dist < min_dist) tp_dist = min_dist;

       double balance = AccountInfoDouble(ACCOUNT_BALANCE);
       double risk_amount = balance * (RiskPercent / 100.0); 
       
       double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE); 
       double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE); 
       
       double sl_ticks = sl_dist / tick_size;
       double calculated_lot = risk_amount / (sl_ticks * tick_value);
       
       double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
       double max_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
       double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
       
       calculated_lot = MathFloor(calculated_lot / step) * step; 
       if(calculated_lot < min_lot) calculated_lot = min_lot;
       if(calculated_lot > max_lot) calculated_lot = max_lot;

       if(signal == "BUY")
       {
       double sl = ask - sl_dist;
       double tp = ask + tp_dist;
       trade.Buy(calculated_lot, sym, ask, sl, tp, "Gemini Portfolio");
       Print(">>> TRADE EXECUTED: BUY ", sym, " | Lot: ", calculated_lot, " | Risk: $", risk_amount);
       }
       else if(signal == "SELL")
       {
       double sl = bid + sl_dist;
       double tp = bid - tp_dist;
       trade.Sell(calculated_lot, sym, bid, sl, tp, "Gemini Portfolio");
       Print(">>> TRADE EXECUTED: SELL ", sym, " | Lot: ", calculated_lot, " | Risk: $", risk_amount);
       }
    }
 }
 }
 }
//+------------------------------------------------------------------+