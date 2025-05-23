{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE NoFieldSelectors #-}
{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}
{-# OPTIONS_GHC -fplugin=Protocols.Plugin #-}

module Blink where

import Clash.Annotations.TH
import Clash.Cores.UART (ValidBaud)
import Clash.Prelude

import Data.Maybe qualified as DM

import Communication
import ConfigGen
import Domain
import Ila
import Packet
import Pmod
import Protocols
import Packet

-- | Resets the ILA trigger whenever we receive an incoming byte from UART
triggerResetUart ::
  (HiddenClockResetEnable dom) =>
  Circuit (CSignal dom (Maybe (BitVector 8))) (CSignal dom Bool)
triggerResetUart = Circuit exposeIn
 where
  exposeIn (incoming, _) = out
   where
    out = (pure (), DM.isJust <$> incoming)

-- | Set the ILA trigger reset state based on the button 0 (TRUE) and button 1 (FALSE)
triggerResetButtons ::
  (HiddenClockResetEnable dom) =>
  Circuit (CSignal dom (BitVector 4)) (CSignal dom Bool)
triggerResetButtons = Circuit exposeIn
 where
  exposeIn (incoming, _) = out
   where
    reg = register False $ liftA2 change incoming reg

    change 1 _ = True
    change 2 _ = False
    change _ r = r

    out = (pure (), reg)

-- | UART ILA demonstration toplevel
topLogicUart ::
  forall dom baud.
  (HiddenClockResetEnable dom, ValidBaud dom baud) =>
  -- | Baud rate of UART
  SNat baud ->
  -- | Buttons
  Signal dom (BitVector 4) ->
  -- | RX
  Signal dom Bit ->
  -- | TX
  Signal dom Bit
topLogicUart baud btns rx = go
 where
  -- Simple demo signal to 'debug'
  counter0 :: (HiddenClockResetEnable dom) => Signal dom (BitVector 9)
  counter0 = register 0 $ satAdd SatWrap 1 <$> counter0
  counter1 :: (HiddenClockResetEnable dom) => Signal dom (BitVector 8)
  counter1 = register 20 $ satAdd SatWrap 1 <$> counter1
  counter2 :: (HiddenClockResetEnable dom) => Signal dom (Signed 10)
  counter2 = register 40 $ satAdd SatWrap 1 <$> counter2

  Circuit main = circuit $ \(rxBit) -> do
    (rxByte, txBit) <- uartDf baud -< (txByte, rxBit)
    packet <-
      ila
        ( ilaConfig
            d100
            20
            "name"
            ( ilaProbe
                (counter0, "c0")
                (counter1, "c1")
                (counter2, "c2")
            )
        )
        ((==300) <$> counter0)
        (pure True)
        -< rxByte
    txByte <- ps2df <| dropMeta -< packet
    idC -< txBit

  go = snd $ main (rx, pure ())

-- | The top entity
topEntity ::
  "CLK" ::: Clock Dom48 ->
  "BTN" ::: Reset Dom48 ->
  "PMOD3" ::: Signal Dom48 PmodBTN ->
  "PMOD1_6" ::: Signal Dom48 Bit ->
  "PMOD1_5" ::: Signal Dom48 Bit
topEntity clk rst btn = withClockResetEnable clk rst enableGen (topLogicUart (SNat @9600) (pack <$> btn))

makeTopEntity 'topEntity
