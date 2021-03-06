{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Test.IO.Warden.Marker where

import           Control.Monad.IO.Class (liftIO)

import           Disorder.Core.IO (testIO)

import           P

import           System.Directory (removeFile)
import           System.IO

import           Test.QuickCheck
import           Test.QuickCheck.Instances ()

import           Test.IO.Warden
import           Test.Warden.Arbitrary ()

import           Warden.Data
import           Warden.Marker

import           X.Control.Monad.Trans.Either (bracketEitherT')

prop_writeFileMarker :: FileMarker -> Property
prop_writeFileMarker fm = testIO $ withTestViewFile $ \vf -> unsafeWarden $ do
  let fm' = fm { fmViewFile = vf }
  fm'' <- bracketEitherT' (writeFileMarker fm' >> pure (fmViewFile fm'))
                         (\vf' -> liftIO . removeFile $ fileToMarker vf')
                         (\vf' -> readFileMarker vf')
  pure $ fm'' === fm'

prop_writeViewMarker :: ViewMarker -> Property
prop_writeViewMarker vm = testIO $ withTestView $ \v -> unsafeWarden $ do
  let vm' = vm { vmView = v }
  writeViewMarker vm'
  vm'' <- readViewMarker $ viewMarkerPath vm'
  pure $ vm'' === vm'

return []
tests :: IO Bool
tests = $forAllProperties $ quickCheckWithResult (stdArgs { maxSuccess = 10 })
