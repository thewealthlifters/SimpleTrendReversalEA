//+------------------------------------------------------------------+
//|                                               CMrdFXStrategy.mqh |
//|                                    Copyright 2017, Erwin Beckers |
//|                                      https://www.erwinbeckers.nl |
//+------------------------------------------------------------------+
#property copyright "Copyright 2017, Erwin Beckers"
#property link      "https://www.erwinbeckers.nl"
#property strict

extern string     _srfilter_                   = " ------- S&R Filter ------------";
extern bool        UseSupportResistanceFilter  = false;
extern int         MaxPipsFromSR               = 30;
extern bool        SR_1Hours                   = false;
extern bool        SR_4Hours                   = false;
extern bool        SR_Daily                    = true;
extern bool        SR_Weekly                   = true;

extern string     __trendfilter                = " ------- SMA 200 Daily Trend Filter ------------";
extern bool        UseSma200TrendFilter        = false;

extern string     __signals__                  = " ------- Candles to look back for confirmation ------------";
extern int        ZigZagCandles                = 10;
extern int        MBFXCandles                  = 10;

#include <CStrategy.mqh>
#include <CZigZag.mqh>
#include <CMBFX.mqh>
#include <CTrendLine.mqh>
#include <CSupportResistance.mqh>
#include <CUtils.mqh>

extern string     __movingaverage__            = " ------- Moving Average Settings ------------";
extern int        MovingAveragePeriod          = 15;
extern int        MovingAverageType            = MODE_SMA;


bool UseMBFX      = true;
bool UseSMA15     = true;
bool UseTrendLine = true;

//--------------------------------------------------------------------
class CMrdFXStrategy : public IStrategy
{
private:
   CSupportResistance* _supportResistanceH1;
   CSupportResistance* _supportResistanceH4;
   CSupportResistance* _supportResistanceD1;
   CSupportResistance* _supportResistanceW1;
   CZigZag*            _zigZag;         
   CMBFX*              _mbfx;         
   CTrendLine*         _trendLine; 
   int                 _indicatorCount;
   CIndicator*         _indicators[];
   CSignal*            _signal;
   string              _symbol;
   
public:
   //--------------------------------------------------------------------
   CMrdFXStrategy(string symbol)
   {
      _symbol              = symbol;
      _supportResistanceH1 = new CSupportResistance(_symbol, PERIOD_H1);
      _supportResistanceH4 = new CSupportResistance(_symbol, PERIOD_H4);
      _supportResistanceD1 = new CSupportResistance(_symbol, PERIOD_D1);
      _supportResistanceW1 = new CSupportResistance(_symbol, PERIOD_W1);
      _zigZag              = new CZigZag();
      _mbfx                = new CMBFX();
      _trendLine           = new CTrendLine();
      _signal              = new CSignal();
         
      _indicatorCount = 1; // zigzag
      if (UseMBFX) _indicatorCount++;
      if (UseTrendLine) _indicatorCount++;
      if (UseSMA15) _indicatorCount++;
      if (UseSma200TrendFilter) _indicatorCount++; 
      if (UseSupportResistanceFilter) _indicatorCount++; 
       
      ArrayResize(_indicators, 10);
      int index=0;
      _indicators[index] = new CIndicator("ZigZag");
      index++;
      
      if (UseMBFX)
      {
         _indicators[index] = new CIndicator("MBFX");
         index++;
      }
      
      if (UseTrendLine)
      {
         _indicators[index] = new CIndicator("Trend");
         index++;
      }
      
      if (UseSMA15) 
      {
         _indicators[index] = new CIndicator("MA15");
         index++;
      }
      
      if (UseSma200TrendFilter)
      {
         _indicators[index] = new CIndicator("MA200");
         index++;
      }
      
      if (UseSupportResistanceFilter) 
      {
        _indicators[index] = new CIndicator("S&R");
        index++;
      }
   }
   
   //--------------------------------------------------------------------
   ~CMrdFXStrategy()
   {
      delete _zigZag;
      delete _mbfx;
      delete _trendLine;
      delete _signal;
      delete _supportResistanceH1;
      delete _supportResistanceH4;
      delete _supportResistanceD1;
      delete _supportResistanceW1;
      
      for (int i=0; i < _indicatorCount;++i)
      {
         delete _indicators[i];
      }
      ArrayFree(_indicators);
   }
   
   //--------------------------------------------------------------------
   CSignal* Refresh()
   {
      _zigZag.Refresh(_symbol);
      _mbfx.Refresh(_symbol);
      _trendLine.Refresh(_symbol);
      
      int  zigZagBar    = -1;
      bool zigZagBuy    = false;
      bool zigZagSell   = false;
      bool mbfxOk       = false;
      bool trendOk      = false;
      bool sma15Ok      = false;
      bool sma200ok     = false;
      
      // Rule #1: a zigzar arrow appears
      for (int bar = ZigZagCandles; bar >= 1;bar--)
      {
         ARROW_TYPE arrow = _zigZag.GetArrow(bar); 
         if (arrow == ARROW_BUY)
         {
            zigZagBuy    = true;
            zigZagSell   = false;
            zigZagBar    = bar;
         }
         if (arrow == ARROW_SELL)
         {
            zigZagBuy    = false;
            zigZagSell   = true;
            zigZagBar    = bar;
         }
      }
         
      // BUY signals
      if (zigZagBuy && zigZagBar > 0)
      {
         // sma 200 trendline
         double ima200 = iMA(_symbol, PERIOD_D1, 200, 0, MODE_SMA,PRICE_CLOSE, 1);
         if ( iClose(_symbol, 0, 1) >= ima200 )  sma200ok = true;
          
         // MBFX should be green at the moment 
         // and should have been below < 30 some candles ago
         int barStart = zigZagBar;
         if (zigZagBar == 1) barStart = 2;
         for (int bar = MathMin(barStart, MBFXCandles); bar >= 1; bar--)
         {
            double red   = _mbfx.RedValue(bar);
            double green = _mbfx.GreenValue(bar);
            if (red < 30 || green < 30)
            {
               mbfxOk  = true;
            }
         }
               
         // trend line should be green at the moment
         if (_trendLine.IsGreen(1))
         {
            trendOk = true;
         }
   
         // rule #4: price should be above 15 SMA 
         double ma1 = iMA(_symbol, 0, MovingAveragePeriod, 0, MovingAverageType, PRICE_CLOSE, 1);
         if ( iClose(_symbol, 0, 1) > ma1 )  
         {
            sma15Ok = true;
         }
      }
      
      
      // SELL signals
      if (zigZagSell && zigZagBar > 0)
      {
         double ima200 = iMA(_symbol, PERIOD_D1, 200, 0, MODE_SMA,PRICE_CLOSE, 1);
         if ( iClose(_symbol, 0, 1) <= ima200 ) sma200ok = true;
          
         // MBFX should now be red
         // and should been above > 70 some candles ago
         int barStart = zigZagBar;
         if (zigZagBar == 1) barStart = 2;
         barStart = MathMin(barStart, MBFXCandles);
         for (int bar = barStart; bar >= 1; bar--)
         {
            double red   = _mbfx.RedValue(bar);
            double green = _mbfx.GreenValue(bar);
            if ( (red > 70 && red < 200) || (green >70 && green < 200))
            {
               mbfxOk = true;
            }
         }
         
         // trend line should now be red 
         if (_trendLine.IsRed(1))
         {
            trendOk = true;
         }
               
         // rule #4: and price below SMA15 on previous candle
         double ma1 = iMA(_symbol, 0, MovingAveragePeriod, 0, MovingAverageType, PRICE_CLOSE, 1);
         if (   iClose(_symbol, 0, 1) < ma1 )
         {
           sma15Ok = true;
         }
      }
      
      // clear indicators
      for (int i=0; i < _indicatorCount;++i)
      {
         _indicators[i].IsValid = false;
      }
      _signal.Reset();
      
      // set indicators
      if (zigZagBar >= 1 && (zigZagBuy || zigZagSell) )
      {
         if (zigZagBuy) 
         {
            _signal.IsBuy    = true;
            _signal.StopLoss = iLow(_symbol, 0, zigZagBar);
         }
         else if (zigZagSell)
         {
            _signal.IsSell   = true;
            _signal.StopLoss = iHigh(_symbol, 0, zigZagBar);
         }
         
         int index=1;
         _indicators[0].IsValid = true;    // zigzag    
         if (UseMBFX)
         {
            _indicators[index].IsValid = mbfxOk;  
             index++;
         }
         if (UseTrendLine)
         {
            _indicators[index].IsValid = trendOk;
            index++;
         }
         
         if (UseSMA15) 
         {
            _indicators[index].IsValid = sma15Ok;
            index++;
         }
        
         if (UseSma200TrendFilter)
         {
            _indicators[index].IsValid = sma200ok; 
            index++;
         }
         
         
        int signalFirstValidBar = GetSignalFirstValid(zigZagBar, zigZagBuy, zigZagSell); 
        if (signalFirstValidBar>0)
        {
          double priceStart    = iClose(_symbol,0, signalFirstValidBar);
          double priceNow      = _utils.BidPrice(_symbol);
          double priceDistance = MathAbs(priceNow - priceStart);
          if (priceDistance > 0) priceDistance = _utils.PriceToPips(_symbol, priceDistance);
          _signal.PipsAway = priceDistance;
          _signal.Age      = GetHours(signalFirstValidBar);
        }
         
         if (UseSupportResistanceFilter)
         {
            bool srValid=false;
            double srLevel;
            if (_signal.IsBuy)
            {
               if (SR_1Hours) srValid |= _supportResistanceH1.IsAtSupport(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_4Hours) srValid |= _supportResistanceH4.IsAtSupport(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_Daily)  srValid |= _supportResistanceD1.IsAtSupport(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_Weekly) srValid |= _supportResistanceW1.IsAtSupport(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               
            }
            else if (_signal.IsSell)
            {
               if (SR_1Hours) srValid |= _supportResistanceH1.IsAtResistance(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_4Hours) srValid |= _supportResistanceH4.IsAtResistance(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_Daily)  srValid |= _supportResistanceD1.IsAtResistance(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               if (SR_Weekly) srValid |= _supportResistanceW1.IsAtResistance(_signal.StopLoss, MaxPipsFromSR, srLevel,false);
               
            }
           _indicators[index].IsValid = srValid;
           index++;
         }
      }
      return _signal;
   }
   
   //--------------------------------------------------------------------
   int GetSignalFirstValid(int zigZagBar, bool zigZagBuy, bool zigZagSell)
   {
     int barStart = zigZagBar;
     if (zigZagBar == 1) barStart = 2;
     barStart = MathMin(barStart, MBFXCandles);
     for (int barMbfx = barStart; barMbfx >= 1; barMbfx--)
     {
        if (zigZagBuy)
        {
          // buy signal
          double red   = _mbfx.RedValue(barMbfx);
          double green = _mbfx.GreenValue(barMbfx);
          if (red < 30 || green < 30)
          {
             //Print("buy mbfx:", barMbfx);
             for (int barTrend=barMbfx; barTrend >=1; barTrend--)
             {
               if (_trendLine.IsGreen(barTrend))
               {
                 //Print("buy trendline:", barTrend);
                 
                 for (int barMA=barTrend; barMA >=1; barMA--)
                 {
                   double ma1 = iMA(_symbol, 0, MovingAveragePeriod, 0, MovingAverageType, PRICE_CLOSE, barMA);
                   if ( iClose(_symbol, 0, barMA) > ma1 )  
                   {
                      //Print("buy sma15:", barMA);
                      return barMA;
                   }
                 }
               }
             }
          }
        }
        else if (zigZagSell)
        {
          // sell signal
          double red   = _mbfx.RedValue(barMbfx);
          double green = _mbfx.GreenValue(barMbfx);
          if ( (red > 70 && red < 200) || (green >70 && green < 200))
          {
             //Print("sell mbfx:", barMbfx);
             for (int barTrend=barMbfx; barTrend >=1; barTrend--)
             {
               if (_trendLine.IsRed(barTrend))
               {
                 //Print("sell trendline:", barTrend);
                 
                 for (int barMA=barTrend; barMA >=1; barMA--)
                 {
                   double ma1 = iMA(_symbol, 0, MovingAveragePeriod, 0, MovingAverageType, PRICE_CLOSE, barMA);
                   if ( iClose(_symbol, 0, barMA) < ma1 )  
                   {
                      //Print("sell ma15:", barMA);
                      return barMA;
                   }
                 }
               }
             }
          }
        }
     }
     return -1;
   }
   
   //--------------------------------------------------------------------
   int GetHours(int bar)
   {
      double dBars = bar;
      double hours = 0;
      switch(Period())
      {
        case PERIOD_M1:
          hours = dBars / 60.0;
        break;
        
        case PERIOD_M5:
          hours = dBars / 12.0;
        break;
        
        case PERIOD_M15:
          hours = dBars / 4.0;
        break;
        
        case PERIOD_M30:
          hours = dBars / 2.0;
        break;
        
        case PERIOD_H1:
          hours = dBars / 1.0;
        break;
        
        case PERIOD_H4:
          hours = dBars * 4.0;
        break;
        
        case PERIOD_D1:
          hours = dBars * 24.0;
        break;
        
        case PERIOD_W1:
          hours = dBars * 24.0 * 7;
        break;
      }
      return MathFloor(hours);
   }
   
   //--------------------------------------------------------------------
   int GetIndicatorCount()
   {
      return _indicatorCount;
   }
   
   //--------------------------------------------------------------------
   CIndicator* GetIndicator(int indicator)
   {
      return _indicators[indicator];
   }
   
   //--------------------------------------------------------------------
   double GetStopLossForOpenOrder()
   {
      _zigZag.Refresh(_symbol);
      
      // find last zigzag arrow
      int zigZagBar = -1;
      ARROW_TYPE arrow = ARROW_NONE;
      for (int bar=0; bar < 200;++bar)
      {
         arrow = _zigZag.GetArrow(bar);
         if (arrow == ARROW_BUY )
         {
            if (OrderType() == OP_BUY) zigZagBar = bar;
            break;
         }
         else if (arrow == ARROW_SELL)
         {
            if (OrderType() == OP_SELL) zigZagBar = bar;
            break;
         }
      }
      if (zigZagBar == 0) zigZagBar=1;
      
      if (zigZagBar > 0)
      {
         if (arrow == ARROW_BUY)
         {
            return iLow(_symbol, 0, zigZagBar);
         }
         else if (arrow == ARROW_SELL)
         {
            return iHigh(_symbol, 0, zigZagBar);
         }
      }
      return 0;
   }
};