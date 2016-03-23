{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Warden.Row.Parser (
    escapedFieldP
  , fieldP
  , rawFieldP
  , rawRecordP
  , sepByByte1P
  ) where

import           Data.Attoparsec.ByteString (Parser)
import           Data.Attoparsec.ByteString (word8, peekWord8, takeWhile, anyWord8)
import           Data.Attoparsec.ByteString (string, endOfInput, choice)
import qualified Data.Attoparsec.ByteString as AB
import           Data.Attoparsec.ByteString.Char8 (decimal, signed, double)
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.Char (ord)
import           Data.Word (Word8)

import qualified Data.Vector as V

import           P

import           Warden.Data.Row

rawRecordP :: Separator -> Parser RawRecord
rawRecordP sep = (RawRecord . V.fromList) <$!> rawFieldP sep `sepByByte1P` sep
{-# INLINE rawRecordP #-}

sepByByte1P :: Parser a -> Separator -> Parser [a]
sepByByte1P p !sep =
  liftM2' (:) p go
  where
    go = do
      peekWord8 >>= \case
        Just c -> if c == sep'
                    then liftM2' (:) (anyWord8 *> p) go
                    else pure []
        Nothing -> pure []

    sep' = unSeparator sep
{-# INLINE sepByByte1P #-}
      
rawFieldP :: Separator -> Parser ByteString
rawFieldP !sep =
  peekWord8 >>= \case
    Just c -> if c == doubleQuote
                then escapedFieldP
                else unescapedFieldP sep
    Nothing -> unescapedFieldP sep
{-# INLINE rawFieldP #-}

-- | We do not unescape the content of escaped fields, as the number of
-- double-quotes present in a text field (as long as it remains consistent)
-- shouldn't affect validation at all.
escapedFieldP :: Parser ByteString
escapedFieldP = do
  void $ word8 doubleQuote
  s <- AB.scan False endOfField
  case BS.unsnoc s of
    Nothing ->
      pure ""
    Just (init, last) ->
      if last == doubleQuote
        then pure init
        else pure s
  where
    endOfField st c =
      if c == doubleQuote
        then Just $ not st
        else if st
          then Nothing
          else Just False
{-# INLINE escapedFieldP #-}

unescapedFieldP :: Separator -> Parser ByteString
unescapedFieldP !sep =
  takeWhile fieldByte
  where
    fieldByte c =
         c /= sep'
      && c /= lineFeed
      && c /= carriageReturn
      && c /= doubleQuote

    sep' = unSeparator sep
{-# INLINE unescapedFieldP #-}

lineFeed :: Word8
lineFeed = fromIntegral $ ord '\n'
{-# INLINE lineFeed #-}

carriageReturn :: Word8
carriageReturn = fromIntegral $ ord '\r'
{-# INLINE carriageReturn #-}

doubleQuote :: Word8
doubleQuote = fromIntegral $ ord '"'
{-# INLINE doubleQuote #-}

fieldP :: Parser ParsedField
fieldP = choice [
    void (signed (decimal :: Parser Integer) <* endOfInput) >> pure ParsedIntegral
  , void (double <* endOfInput) >> pure ParsedReal
  , void (boolP <* endOfInput) >> pure ParsedBoolean
  ]
{-# INLINE fieldP #-}

boolP :: Parser ()
boolP = trueP <|> falseP
  where
    trueP = do
      void . word8 . fromIntegral $ ord 't'
      peekWord8 >>= \case
        Nothing -> pure ()
        Just _ -> void $ string "rue"

    falseP = do
      void . word8 . fromIntegral $ ord 'f'
      peekWord8 >>= \case
        Nothing -> pure ()
        Just _ -> void $ string "alse"
{-# INLINE boolP #-}