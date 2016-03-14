{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE LambdaCase #-}

import           BuildInfo_ambiata_warden

import           Control.Monad.Trans.Resource (runResourceT)

import           Data.Char (ord)
import           Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text.IO as T
import qualified Data.Text as T

import           Options.Applicative

import           P

import           System.Exit (exitSuccess, exitFailure)
import           System.IO (IO, FilePath, print, putStrLn)

import           Warden.Commands
import           Warden.Data
import           Warden.Error
import           Warden.Param
import           Warden.Schema

import           X.Control.Monad.Trans.Either (mapEitherT)
import           X.Control.Monad.Trans.Either.Exit (orDie)
import           X.Options.Applicative

data Command =
    Check !View !CheckParams
  | SingleFileCheck !ViewFile !CheckParams
  | Infer !Verbosity ![FilePath]
  deriving (Eq, Show)

main :: IO ()
main = do
  dispatch (safeCommand wardenP) >>= \case
    VersionCommand -> do
      putStrLn ("warden: " <> buildInfoVersion)
      exitSuccess
    RunCommand DryRun c -> do
      print c
      exitSuccess
    RunCommand RealRun cmd -> do
      wps <- buildWardenParams . WardenVersion $ T.pack buildInfoVersion
      run wps cmd

run :: WardenParams -> Command -> IO ()
run wps (Check v ps) = do
  r <- orDie renderWardenError . mapEitherT runResourceT $ check wps v ps
  finishCheck (checkVerbosity ps) r
run wps (SingleFileCheck vf ps) = do
  r <- orDie renderWardenError . mapEitherT runResourceT $ fileCheck wps vf ps
  finishCheck (checkVerbosity ps) r
run _wps (Infer v fs) = do
  s <- orDie renderWardenError . mapEitherT runResourceT $ infer v fs
  T.writeFile "schema.json" $ renderSchema s

finishCheck :: Verbosity -> NonEmpty CheckResult -> IO ()
finishCheck verb rs = do
  when (verb == Verbose) $
    mapM_ T.putStrLn . NE.toList . (=<<) renderCheckResult $ rs
  if checkHasFailures rs
    then exitFailure
    else exitSuccess

wardenP :: Parser Command
wardenP = subparser $
     command' "check" "Run checks over a view." checkP
  <> command' "check-file" "Run checks over a single file." fileCheckP
  <> command' "infer" "Attempt to infer a schema from a set of metadata files." inferP

checkP :: Parser Command
checkP = Check <$> viewP <*> checkParamsP

fileCheckP :: Parser Command
fileCheckP = SingleFileCheck <$> viewFileP <*> checkParamsP

inferP :: Parser Command
inferP = Infer <$> verbosityP <*> some markerFileP

checkParamsP :: Parser CheckParams
checkParamsP = CheckParams <$> separatorP
                           <*> schemaFileP
                           <*> lineBoundP
                           <*> verbosityP
                           <*> forceP

markerFileP :: Parser FilePath
markerFileP = strArgument $
     metavar "MARKER-FILE"
  <> help "Path to view marker file(s) from `warden check`."

viewP :: Parser View
viewP = View <$> (strArgument $
     metavar "VIEW"
  <> help "Path to local copy of view.")

viewFileP :: Parser ViewFile
viewFileP = argument (eitherReader viewFileR) $
      metavar "VIEW-FILE"
   <> help "Path to local view file."
  where
    viewFileR fp = case viewFile fp of
      Left _ -> Left $ "invalid view file: " <> fp
      Right vf -> Right vf

separatorP :: Parser Separator
separatorP = option (eitherReader separator) $
     long "separator"
  <> short 's'
  <> metavar "SEPARATOR"
  <> value (Separator . fromIntegral $ ord '|')
  <> help "Field separator for view (e.g., pipe or comma). Defaults to '|'."
  where
    separator x = maybeToRight ("Invalid separator " <> x) $ valid' x
    valid' [x] = if ord x >= 32 && ord x < 128
      then Just . Separator . fromIntegral $ ord x
      else Nothing
    valid' _   = Nothing
      
lineBoundP :: Parser LineBound
lineBoundP = LineBound <$> (option auto $
     long "max-line-length"
  <> short 'b'
  <> metavar "LINE_LENGTH"
  <> value 65536
  <> help "Maximum line length. Defaults to 65536.")

verbosityP :: Parser Verbosity
verbosityP =
  flag Quiet Verbose $
       long "verbose"
    <> short 'v'
    <> help "Verbose output."

forceP :: Parser Force
forceP =
  flag NoForce Force $
       long "force"
    <> short 'f'
    <> help "Overwrite existing marker files."

schemaFileP :: Parser (Maybe SchemaFile)
schemaFileP = maybe Nothing (Just . SchemaFile) <$> (optional . strOption $
     long "schema"
  <> metavar "SCHEMA-FILE"
  <> help "JSON-format schema against which to validate the dataset.")
