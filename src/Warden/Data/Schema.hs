{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Warden.Data.Schema (
    Schema(..)
  , SchemaField(..)
  , SchemaFile(..)
  , SchemaVersion(..)
  , renderSchemaFile
  , schemaFieldType
  ) where

import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Vector (Vector)

import           P

import           System.IO (FilePath)

import           Warden.Data.Field
import           Warden.Data.Row

newtype SchemaFile =
  SchemaFile {
      unSchemaFile :: FilePath
  } deriving (Eq, Show)

renderSchemaFile :: SchemaFile -> Text
renderSchemaFile = T.pack . unSchemaFile

data SchemaVersion =
    SchemaV1
  deriving (Eq, Show, Enum, Bounded)
-- FIXME: get rid of FieldCount
data Schema = Schema !SchemaVersion !FieldCount !(Vector SchemaField)
  deriving (Eq, Show)

-- | This will contain more data in the future, e.g., summary statistics for
-- numeric types.
data SchemaField = SchemaField !FieldType
  deriving (Eq, Show)

schemaFieldType :: SchemaField -> FieldType
schemaFieldType (SchemaField ft) = ft
