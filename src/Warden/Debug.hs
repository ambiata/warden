{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Warden.Debug (
    debugPrintLn
  ) where

import           Data.Text.IO (putStrLn)

import           P

import           System.IO (IO)

import           Warden.Data.Param

debugPrintLn :: Verbosity -> Text -> IO ()
debugPrintLn verb msg =
  when (verb == Verbose) $ putStrLn msg
