{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}

module Warden.Data.Row (
    FieldCount(..)
  , FieldLookCount(..)
  , FieldReservoirAcc(..)
  , LineBound(..)
  , ObservationCount(..)
  , ParsedField(..)
  , RawRecord(..)
  , Row(..)
  , RowCount(..)
  , SVParseState(..)
  , Separator(..)
  , badRows
  , charToSeparator
  , combineFieldLooks
  , emptyLookCountVector
  , fieldLooks
  , initialSVParseState
  , numericState
  , numFields
  , piiState
  , renderFieldCount
  , renderObservationCount
  , renderParsedField
  , renderRowCount
  , reservoirState
  , separatorToChar
  , textCounts
  , totalRows
) where

import           Control.DeepSeq.Generics (genericRnf)
import           Control.Lens (makeLenses)

import           Data.ByteString (ByteString)
import           Data.Char (chr, ord)
import           Data.Set (Set)
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as VU
import           Data.Vector.Unboxed.Deriving (derivingUnbox)
import           Data.Word (Word8)

import           GHC.Generics (Generic)

import           P

import           Prelude (fromEnum)

import           Warden.Data.Field
import           Warden.Data.Numeric
import           Warden.Data.PII
import           Warden.Data.Sampling.Reservoir
import           Warden.Data.TextCounts

newtype RawRecord =
  RawRecord {
    unRawRecord :: V.Vector ByteString
  } deriving (Eq, Show, Generic)

instance NFData RawRecord where rnf = genericRnf

newtype LineBound =
  LineBound {
    unLineBound :: Int
  } deriving (Eq, Show, Generic)

instance NFData LineBound where rnf = genericRnf

newtype FieldCount =
  FieldCount {
    unFieldCount :: Int
  } deriving (Eq, Show, Ord, Num, Generic)

instance NFData FieldCount where rnf = genericRnf

renderFieldCount :: FieldCount -> Text
renderFieldCount = renderIntegral . unFieldCount

newtype ObservationCount =
  ObservationCount {
    unObservationCount :: Int64
  } deriving (Eq, Show, Ord, Num, Generic)

$(derivingUnbox "ObservationCount"
  [t| ObservationCount -> Int64 |]
  [| \(ObservationCount x) -> x |]
  [| \x -> (ObservationCount x) |])

instance NFData ObservationCount where rnf = genericRnf

renderObservationCount :: ObservationCount -> Text
renderObservationCount (ObservationCount n) = renderIntegral n

newtype Separator =
  Separator {
    unSeparator :: Word8
  } deriving (Eq, Show, Generic)

instance NFData Separator where rnf = genericRnf

charToSeparator :: Char -> Separator
charToSeparator = Separator . fromIntegral . ord

separatorToChar :: Separator -> Char
separatorToChar = chr . fromIntegral . unSeparator

-- | Raw record. Can be extended to support JSON objects as well as xSV if
--   needed.
data Row =
    SVFields !(V.Vector ByteString)
  | RowFailure !Text
  deriving (Eq, Show, Generic)

instance NFData Row where rnf = genericRnf

newtype RowCount =
  RowCount {
    unRowCount :: Int64
  } deriving (Eq, Show, Ord, Num, Generic)

instance NFData RowCount where rnf = genericRnf

renderRowCount :: RowCount -> Text
renderRowCount = T.pack . show . unRowCount

emptyLookCountVector :: VU.Vector ObservationCount
emptyLookCountVector =
  let ixs = fmap fromEnum ([minBound..maxBound] :: [FieldLooks]) in
  VU.replicate (length ixs) (ObservationCount 0)

combineFieldLooks :: FieldLookCount
                  -> FieldLookCount
                  -> FieldLookCount
combineFieldLooks NoFieldLookCount NoFieldLookCount = NoFieldLookCount
combineFieldLooks (FieldLookCount !x) NoFieldLookCount = FieldLookCount x
combineFieldLooks NoFieldLookCount (FieldLookCount !y) = FieldLookCount y
combineFieldLooks (FieldLookCount !x) (FieldLookCount !y) = FieldLookCount . uncurry combine' $ matchSize x y
  where
    combine' = V.zipWith addLooks

    addLooks a b = VU.accumulate (+) a $ VU.indexed b

    -- To retain some sanity in the event of mismatched field counts.
    matchSize a b =
      let la = V.length a
          lb = V.length b
          ln = max la lb
          na = V.concat [a, V.replicate (ln - la) emptyLookCountVector]
          nb = V.concat [b, V.replicate (ln - lb) emptyLookCountVector] in
      (na, nb) 

data FieldLookCount =
    FieldLookCount !(V.Vector (VU.Vector ObservationCount))
  | NoFieldLookCount
  deriving (Eq, Show, Generic)

instance NFData FieldLookCount where rnf = genericRnf

-- FIXME: generalize
data FieldReservoirAcc =
    NoFieldReservoirAcc
  | FieldReservoirAcc !(V.Vector ReservoirAcc)
  deriving (Generic)

instance NFData FieldReservoirAcc where rnf = genericRnf

data SVParseState =
  SVParseState {
    _badRows :: !RowCount
  , _totalRows :: !RowCount
  -- | Unique counts of fields per row.
  , _numFields :: !(Set FieldCount)
  -- | Table of guesses of data type for each field.
  , _fieldLooks :: !FieldLookCount
  -- | Hashes of unique field values, used to determine if a field is
  -- categorical. 
  , _textCounts :: !TextCounts
  -- | Summary statistics for numeric fields.
  , _numericState :: !FieldNumericState
  -- | Uniform sample of values from numeric fields.
  , _reservoirState :: !FieldReservoirAcc
  , _piiState :: !PIIObservations
  } deriving (Generic)

instance NFData SVParseState where rnf = genericRnf

makeLenses ''SVParseState

-- | Only the types we rely on an attoparsec parser to detect (cf. bool, which
-- is done in C, and text, which is implied by failure of the other parsers).
data ParsedField =
    ParsedIntegral
  | ParsedReal
  deriving (Eq, Show, Generic, Enum, Bounded)

instance NFData ParsedField where rnf = genericRnf

renderParsedField :: ParsedField
                  -> Text
renderParsedField = T.pack . show

initialSVParseState :: SVParseState
initialSVParseState =
  SVParseState
    0
    0
    S.empty
    NoFieldLookCount
    NoTextCounts
    NoFieldNumericState
    NoFieldReservoirAcc
    NoPIIObservations
