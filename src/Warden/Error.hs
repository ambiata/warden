{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Warden.Error (
    WardenError(..)
  , InferenceError(..)
  , LoadError(..)
  , MarkerError(..)
  , SampleError(..)
  , SchemaError(..)
  , TraversalError(..)
  , ValidationFailure(..)
  , renderInferenceError
  , renderLoadError
  , renderMarkerError
  , renderSampleError
  , renderSchemaError
  , renderTraversalError
  , renderValidationFailure
  , renderWardenError
) where

import           P

import           Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T

import           System.IO (FilePath)

import           Warden.Data.Field
import           Warden.Data.Param
import           Warden.Data.Row
import           Warden.Data.Schema
import           Warden.Data.TextCounts
import           Warden.Data.View

data WardenError =
    WardenLoadError LoadError
  | WardenNotImplementedError
  | WardenTraversalError TraversalError
  | WardenMarkerError MarkerError
  | WardenSchemaError SchemaError
  | WardenInferenceError InferenceError
  | WardenSampleError SampleError
  deriving (Eq, Show)

renderWardenError :: WardenError
                  -> Text
renderWardenError = ("warden: " <>) . render'
  where
    render' (WardenLoadError le) = renderLoadError le
    render' WardenNotImplementedError = "implement me!"
    render' (WardenTraversalError te) = renderTraversalError te
    render' (WardenMarkerError me) = renderMarkerError me
    render' (WardenSchemaError se) = renderSchemaError se
    render' (WardenInferenceError ie) = renderInferenceError ie
    render' (WardenSampleError se) = renderSampleError se

data LoadError =
    RowDecodeFailed ViewFile Text
  deriving (Eq, Show)

renderLoadError :: LoadError -> Text
renderLoadError = ("error loading view: " <>) . render'
  where
    render' (RowDecodeFailed vf e) = T.concat [
        "failed to decode row data in "
      , renderViewFile vf
      , " : "
      , e
      ]

data TraversalError =
    MaxDepthExceeded
  | EmptyView
  | NonViewFiles [NonViewFile]
  deriving (Eq, Show)

renderTraversalError :: TraversalError -> Text
renderTraversalError = ("traversal error: " <>) . render'
  where
    render' MaxDepthExceeded = "maximum traversal depth exceeded - make sure you're pointing to the top level of a view."
    render' EmptyView = "no files found in view"
    render' (NonViewFiles fs) =
         "extra files which don't seem to be part of a view: "
      <> (T.intercalate ", " $ renderNonViewFile <$> fs)

data MarkerError =
    MarkerDecodeError FilePath Text
  | ViewMarkerExistsError View FilePath
  | MarkerFileMismatchError ViewFile ViewFile
  | FileMarkerExistsError ViewFile
  | MarkerViewMismatchError View View
  | FileMarkerVersionError ViewFile
  | ViewMarkerVersionError View
  deriving (Eq, Show)

renderMarkerError :: MarkerError -> Text
renderMarkerError = ("marker error: " <>) . render'
  where
    render' (MarkerDecodeError fp t) =
      "failed to decode marker at " <> T.pack fp <> ": " <> t
    render' (ViewMarkerExistsError v mf) = T.concat [
        "marker already exists for view "
      , renderView v
      , " - remove "
      , T.pack mf
      , " or run with -f if you'd like to run the view checks again"
      ]
    render' (FileMarkerExistsError vf) = T.concat [
        "marker already exists for view file "
      , T.pack (viewFilePath vf)
      , " - remove it, or run with -f if you'd like to run the view checks again"
      ]
    render' (MarkerFileMismatchError a b) = T.concat [
        "cannot combine markers for files "
      , renderViewFile a
      , " and "
      , renderViewFile b
      ]
    render' (MarkerViewMismatchError a b) = T.concat [
        "cannot combine markers for views "
      , renderView a
      , " and "
      , renderView b
      ]
    render' (FileMarkerVersionError vf) = T.concat [
        "incompatible versions when combining markers for view file "
      , renderViewFile vf
      ]
    render' (ViewMarkerVersionError v) = T.concat [
        "incompatible versions when combining markers for view "
      , renderView v
      ]

data SchemaError =
    SchemaDecodeError SchemaFile Text
  deriving (Eq, Show)

renderSchemaError :: SchemaError -> Text
renderSchemaError = ("schema error: " <>) . render'
  where
    render' (SchemaDecodeError sf t) =
      "failed to decode schema at " <> renderSchemaFile sf <> ": " <> t

data InferenceError =
    NoViewMarkersError
  | MarkerValidationFailure ValidationFailure
  | EmptyFieldHistogram
  | NoMinimalFieldTypes FieldIndex
  | ZeroRowCountError
  | NoTextCountError
  | NoTextCountForField FieldIndex
  | CompatibleFieldsGTRowCount RowCount [CompatibleEntries]
  | InsufficientRowsForFormInference RowCount TextFreeformThreshold
  deriving (Eq, Show)

renderInferenceError :: InferenceError -> Text
renderInferenceError = ("inference error: " <>) . render'
  where
    render' NoViewMarkersError =
      "No view markers provided."
    render' (MarkerValidationFailure vf) =
      "Invalid view markers: " <> renderValidationFailure vf
    render' EmptyFieldHistogram =
      "No counts in field histogram. This should be impossible."
    render' (NoMinimalFieldTypes ix) = T.concat [
        "No minimal field types in field histogram for field "
      , renderFieldIndex ix
      , ". This should be impossible."
      ]
    render' ZeroRowCountError =
      "Total row count reported by view markers is zero."
    render' NoTextCountError =
      "No text counts to use for form inference."
    render' (NoTextCountForField i) =
      "No text counts to use for form inference on field " <> renderFieldIndex i
    render' (CompatibleFieldsGTRowCount rc cs) = T.concat [
        "Fields have observation counts higher than the total row count "
      , renderRowCount rc
      , " : "
      , T.intercalate ", " (renderCompatibleEntries <$> cs)
      ]
    render' (InsufficientRowsForFormInference rc fft) = T.concat [
        "cannot infer form - total row count "
      , renderRowCount rc
      , " smaller than check freeform threshold "
      , renderTextFreeformThreshold fft
      ]

data ValidationFailure =
    ViewMarkerMismatch Text Text Text
  | NoFieldCounts
  | ChecksMarkedFailed (NonEmpty RunId)
  deriving (Eq, Show)

renderValidationFailure :: ValidationFailure -> Text
renderValidationFailure f = "Validation failure: " <> render' f
  where
    render' (ViewMarkerMismatch t x y) = T.concat [
        "mismatch: "
      , t
      , ": "
      , x
      , " /= "
      , y
      ]
    render' NoFieldCounts = "No field counts to perform inference on."
    render' (ChecksMarkedFailed rids) = "Some markers recorded a failed check status and cannot be used in inference: " <> (T.intercalate ", " . NE.toList $ renderRunId <$> rids)

data SampleError =
    NumericFieldMismatch
  | ViewMismatch
  | NoNumericSummaries !FilePath
  deriving (Eq, Show)

renderSampleError :: SampleError -> Text
renderSampleError = ("sample error: " <>) . render'
  where
    render' NumericFieldMismatch =
      "mismatch in field numeric types when combining markers"
    render' ViewMismatch =
      "mismatched views in provided markers"
    render' (NoNumericSummaries f) =
      "file contains no numeric summaries: " <> (T.pack f)

