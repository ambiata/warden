{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Warden.Serial.Json.Row(
    fromFieldCount
  , toFieldCount
  , fromSVParseState
  , toSVParseState
  , toFieldArray
  , fromFieldArray
  , toLineBound
  , fromLineBound
  , toSeparator
  , fromSeparator
  ) where

import           Data.Aeson ((.:), (.:?), (.=), object, parseJSON, toJSON)
import           Data.Aeson.Types (Value(..), Parser, typeMismatch)
import           Data.Array (elems, indices, array)
import qualified Data.Array as A
import           Data.Char (chr, ord)
import           Data.List (zip)
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Vector as V

import           P

import           Warden.Data.Row
import           Warden.Data.Field
import           Warden.Serial.Json.Field

fromSeparator :: Separator -> Value
fromSeparator (Separator s) = String . T.pack . pure . chr $ fromIntegral s

toSeparator :: Value -> Parser Separator
toSeparator (String s) = case T.unpack s of
  [s'] -> pure . Separator . fromIntegral $ ord s'
  _ -> fail $ "invalid separator: " <> T.unpack s
toSeparator x = typeMismatch "Warden.Data.Row.Separator" x

fromLineBound :: LineBound -> Value
fromLineBound (LineBound n) = toJSON n

toLineBound :: Value -> Parser LineBound
toLineBound (Number n) = LineBound <$> parseJSON (Number n)
toLineBound x = typeMismatch "Warden.Data.Row.LineBound" x

fromRowCount :: RowCount -> Value
fromRowCount (RowCount n) = toJSON n

toRowCount :: Value -> Parser RowCount
toRowCount (Number n) = RowCount <$> parseJSON (Number n)
toRowCount x          = typeMismatch "Warden.Data.Row.RowCount" x

fromFieldCount :: FieldCount -> Value
fromFieldCount (FieldCount n) = toJSON n

toFieldCount :: Value -> Parser FieldCount
toFieldCount (Number n) = FieldCount <$> parseJSON (Number n)
toFieldCount x          = typeMismatch "Warden.Data.Row.FieldCount" x

fromFieldArray :: A.Array FieldLooks ObservationCount -> Value
fromFieldArray a =
  let is = fromFieldLooks <$> indices a
      vs = fmap (toJSON . unObservationCount) $ elems a in
  toJSON . fmap fromAssoc $ zip is vs
  where
    fromAssoc (i, v) = object [
        "looks" .= i
      , "count" .= v
      ]

toFieldArray :: Value -> Parser (A.Array FieldLooks ObservationCount)
toFieldArray (Array os) = do
  as <- mapM toAssoc $ V.toList os
  pure . array (minBound, maxBound) $ as
  where
    toAssoc (Object o) = do
      looks <- toFieldLooks =<< (o .: "looks")
      count' <- fmap ObservationCount $ parseJSON =<< (o .: "count")
      pure (looks, count')
    toAssoc x = typeMismatch "(Warden.Data.Row.FieldLooks, Integer)" x
toFieldArray x = typeMismatch "Array Warden.Data.Row.FieldLooks Integer" x

fromSVParseState :: SVParseState -> Value
fromSVParseState (SVParseState br tr nfs fas) = object $ [
    "bad-rows" .= fromRowCount br
  , "total-rows" .= fromRowCount tr
  , "field-counts" .= (fmap fromFieldCount $ S.toList nfs)
  ] <> case fas of
         NoFieldLookCount ->
           []
         FieldLookCount fas' ->
           ["field-looks" .= (fmap fromFieldArray $ V.toList fas')]

toSVParseState :: Value -> Parser SVParseState
toSVParseState (Object o) = do
  br <- toRowCount =<< (o .: "bad-rows")
  tr <- toRowCount =<< (o .: "total-rows")
  nfs <- fmap S.fromList $ mapM toFieldCount =<< (o .: "field-counts")
  fas <- maybe (pure NoFieldLookCount) (fmap FieldLookCount . mapM toFieldArray) =<< (o .:? "field-looks")
  pure $ SVParseState br tr nfs fas
toSVParseState x          = typeMismatch "Warden.Data.Row.SVParseState" x
