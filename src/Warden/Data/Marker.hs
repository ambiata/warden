{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}

module Warden.Data.Marker (
    CheckResultSummary(..)
  , CheckResultType(..)
  , DateRange(..)
  , MarkerFailure(..)
  , MarkerStatus(..)
  , RowCountSummary(..)
  , ViewMarker(..)
  , ViewMetadata(..)
  , dateRange
  , filePathChar
  , mkViewMarker
  , viewMarkerPath
  ) where

import           Control.DeepSeq.Generics (genericRnf)

import           Data.Attoparsec.Text (Parser)
import           Data.Attoparsec.Text (satisfy)
import           Data.Char (ord)
import           Data.List.NonEmpty (NonEmpty)
import           Data.Set (Set)
import qualified Data.Set as S
import qualified Data.Text as T

import           Delorean.Local.Date (Date, renderDate)
import           Delorean.Local.DateTime (DateTime(..))

import           GHC.Generics (Generic)

import           System.FilePath (joinPath)
import           System.IO (FilePath)

import           P

import           Warden.Data.Check
import           Warden.Data.Numeric
import           Warden.Data.Param
import           Warden.Data.Row
import           Warden.Data.TextCounts
import           Warden.Data.View

data CheckResultType =
    FileResult
  | RowResult
  deriving (Eq, Show, Ord, Bounded, Enum, Generic)

instance NFData CheckResultType where rnf = genericRnf

newtype MarkerFailure =
  MarkerFailure {
    unMarkerFailure :: NonEmpty Text
  } deriving (Eq, Show, Generic)

instance NFData MarkerFailure where rnf = genericRnf

data MarkerStatus =
    MarkerPass
  | MarkerFail !MarkerFailure
  deriving (Eq, Show, Generic)

instance NFData MarkerStatus where rnf = genericRnf

data CheckResultSummary =
  CheckResultSummary {
      summaryStatus :: !MarkerStatus
    , summaryDescription :: !CheckDescription
    , summaryResultType :: !CheckResultType
  } deriving (Eq, Show, Generic)

instance NFData CheckResultSummary where rnf = genericRnf

data DateRange =
    NoDates
  | DateRange Date Date
  deriving (Eq, Show, Generic)

instance NFData DateRange where rnf = genericRnf

dateRangePartition :: DateRange -> Text
dateRangePartition (DateRange start end) = T.concat [
    renderDate start
  , "_"
  , renderDate end
  ]
dateRangePartition NoDates = "no-dates"

dateRange :: Set Date -> DateRange
dateRange ds
  | S.null ds = NoDates
  | otherwise = DateRange (S.findMin ds) (S.findMax ds)

summarizeFailures :: NonEmpty Failure -> MarkerFailure
summarizeFailures fs = MarkerFailure $ renderFailure <$> fs

summarizeStatus :: CheckStatus -> MarkerStatus
summarizeStatus CheckPassed = MarkerPass
summarizeStatus (CheckFailed fs) = MarkerFail $ summarizeFailures fs

summarizeResult :: CheckResultType -> CheckDescription -> CheckStatus -> CheckResultSummary
summarizeResult typ dsc st =
  let sst = summarizeStatus st in
  CheckResultSummary sst dsc typ

viewMarkerPath :: ViewMarker -> FilePath
viewMarkerPath vm =
  let meta = vmMetadata vm
      wps = vmWardenParams vm
      view = unView $ vmView vm
      ts = T.unpack . renderDateTimeDate $ vmTimestamp vm
      dates = vmDates meta
      dr = T.unpack . dateRangePartition $ dateRange dates
      rid = T.unpack . renderRunId $ wpRunId wps in
  joinPath [
      "_warden"
    , "marker"
    , "view"
    , view
    , dr
    , ts
    , rid <> ".warden"
    ]
  where
    renderDateTimeDate (DateTime d _t) =
      renderDate d

filePathChar :: Parser Char
filePathChar = satisfy (not . bad)
  where
    bad c = or [
        -- This fails some filenames which POSIX might call valid; this is
        -- by design.
        (ord c) < 32
      , c == '/'
      ]

data ViewMarker =
  ViewMarker {
    vmWardenParams :: !WardenParams
  , vmView :: !View
  , vmTimestamp :: !DateTime
  , vmCheckResults :: ![CheckResultSummary]
  , vmMetadata :: !ViewMetadata
  } deriving (Eq, Show, Generic)

instance NFData ViewMarker where rnf = genericRnf

mkViewMarker :: WardenParams
             -> View
             -> CheckDescription
             -> DateTime
             -> ViewMetadata
             -> CheckStatus
             -> ViewMarker
mkViewMarker wps v dsc dt vm cs =
  let crs = [summarizeResult RowResult dsc cs] in
  ViewMarker wps v dt crs vm

data RowCountSummary =
  RowCountSummary {
    rcsBadRows :: !RowCount
  , rcsTotalRows :: !RowCount
  , rcsNumFields :: !(Set FieldCount)
  , rcsFieldLooks :: !FieldLookCount
  , rcsTextCounts :: !TextCounts
  , rcsNumericSummaries :: !NumericFieldSummary
  } deriving (Eq, Show, Generic)

instance NFData RowCountSummary where rnf = genericRnf

data ViewMetadata =
  ViewMetadata {
      vmViewCounts :: !RowCountSummary
    , vmCheckParams :: !CheckParams
    , vmDates :: !(Set Date)
    , vmViewFiles :: !(Set ViewFile)
  } deriving (Eq, Show, Generic)

instance NFData ViewMetadata where rnf = genericRnf
