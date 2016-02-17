{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}

module Warden.Data.Check (
    CheckDescription(..)
  , CheckResult(..)
  , CheckStatus(..)
  , Failure(..)
  , FileCheck(..)
  , Insanity(..)
  , RowFailure(..)
  , checkHasFailures
  , checkStatusFailed
  , isCheckFailure
  , renderFailure
  , renderCheckResult
  , renderCheckStatus
  , resolveCheckStatus
  ) where

import           Data.List.NonEmpty (NonEmpty, (<|), nonEmpty)
import qualified Data.List.NonEmpty as NE
import           Data.Text (Text)
import qualified Data.Text as T

import           P

import           System.IO

import           Warden.Data.Row
import           Warden.Data.View
import           Warden.Error

import           X.Control.Monad.Trans.Either (EitherT)

newtype CheckDescription =
  CheckDescription {
    unCheckDescription :: Text
  } deriving (Eq, Show)

renderCheckDescription :: CheckDescription -> Text
renderCheckDescription = unCheckDescription

data FileCheck =
    FileCheck !CheckDescription (ViewFile -> EitherT WardenError IO CheckStatus)

data CheckResult =
    FileCheckResult !CheckDescription !ViewFile !CheckStatus
  | RowCheckResult !CheckDescription !CheckStatus
  deriving (Eq, Show)

isCheckFailure :: CheckResult -> Bool
isCheckFailure (FileCheckResult _ _ s) = checkStatusFailed s
isCheckFailure (RowCheckResult _ s)    = checkStatusFailed s

checkHasFailures :: NonEmpty CheckResult -> Bool
checkHasFailures rs = any isCheckFailure $ NE.toList rs

data Verbosity =
    Verbose
  | Quiet
  deriving (Eq, Show)

-- FIXME: verbosity
renderCheckResult :: CheckResult -> NonEmpty Text
renderCheckResult (FileCheckResult cd vf st) =
  header <| (renderCheckStatus st)
  where
    header = T.concat [
        "file "
      , renderViewFile vf
      , ": "
      , renderCheckDescription cd
      ]
renderCheckResult (RowCheckResult cd st) =
  header <| (renderCheckStatus st)
  where
    header = T.concat [
        "row: "
      , renderCheckDescription cd
      ]

data CheckStatus = CheckPassed | CheckFailed !(NonEmpty Failure)
  deriving (Eq, Show)

checkStatusFailed :: CheckStatus -> Bool
checkStatusFailed CheckPassed = False
checkStatusFailed (CheckFailed _) = True

renderCheckStatus :: CheckStatus -> NonEmpty Text
renderCheckStatus CheckPassed =
  pure "passed"
renderCheckStatus (CheckFailed fs) =
  "failed: " <| (renderFailure <$> fs)

resolveCheckStatus :: NonEmpty CheckStatus -> CheckStatus
resolveCheckStatus sts = case allFailures of
  Nothing -> CheckPassed
  Just fs -> CheckFailed fs
  where
    allFailures = nonEmpty $ concatMap failures (NE.toList sts)

    failures CheckPassed      = []
    failures (CheckFailed fs) = NE.toList fs

instance Ord CheckStatus where
  compare CheckPassed (CheckFailed _)     = LT
  compare CheckPassed CheckPassed         = EQ
  compare (CheckFailed _) CheckPassed     = GT
  compare (CheckFailed _) (CheckFailed _) = EQ

data Failure =
    SanityCheckFailure !Insanity
  | RowCheckFailure !RowFailure
  deriving (Eq, Show)

data Insanity =
    EmptyFile
  | IrregularFile
  deriving (Eq, Show)

data RowFailure =
    FieldCountMismatch ![FieldCount]
  | ZeroRows
  | HasBadRows !RowCount
  deriving (Eq, Show)

renderFailure :: Failure -> Text
renderFailure (SanityCheckFailure f) =
  "sanity check failed: " <> renderInsanity f
renderFailure (RowCheckFailure f) =
  "row check failed: " <> renderRowFailure f

renderInsanity :: Insanity -> Text
renderInsanity EmptyFile = "file of zero size"
renderInsanity IrregularFile = "not a regular file"

renderRowFailure :: RowFailure -> Text
renderRowFailure (FieldCountMismatch cs) =
  "differing field counts: " <> T.pack (show cs)
renderRowFailure ZeroRows =
  "no rows in xSV document"
renderRowFailure c =
  T.pack (show c) <> " rows failed to parse"


