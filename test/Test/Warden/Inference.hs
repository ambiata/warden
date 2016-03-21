{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Warden.Inference where

import           Control.Lens (view)

import           Data.List (take, repeat)
import           Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import           Data.Semigroup ((<>))
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Vector.Unboxed as VU

import           Disorder.Core.Property (failWith)
import           Disorder.Core.UniquePair (UniquePair(..))
import           Disorder.Corpus (muppets)

import           P hiding ((<>))

import           System.IO (IO)

import           Test.QuickCheck
import           Test.Warden
import           Test.Warden.Arbitrary

import           Warden.Data
import           Warden.Error
import           Warden.Inference

prop_fieldLookSum :: NonEmpty ViewMarker -> Property
prop_fieldLookSum vms =
  let total = sum $ fmap (sumFLC . view fieldLooks . vmViewCounts . vmMetadata) vms
      total' = sumFLC $ fieldLookSum vms in
  total === total'

prop_viewMarkerMismatch_same :: ViewMarker -> Property
prop_viewMarkerMismatch_same vm =
  (isRight $ viewMarkerMismatch vm vm) === True

prop_viewMarkerMismatch_different :: ViewMarker -> UniquePair View -> Property
prop_viewMarkerMismatch_different vm (UniquePair va vb) =
  let vma = vm { vmView = va }
      vmb = vm { vmView = vb } in
  (isRight $ viewMarkerMismatch vma vmb) === False

prop_viewMarkerMismatch_different_fft :: ViewMarker -> UniquePair TextFreeformThreshold -> Property
prop_viewMarkerMismatch_different_fft vm (UniquePair ta tb) =
  let ps = vmCheckParams $ vmMetadata vm
      psa = ps { checkFreeformThreshold = ta }
      psb = ps { checkFreeformThreshold = tb }
      vma = vm { vmMetadata = ((vmMetadata vm) { vmCheckParams = psa }) }
      vmb = vm { vmMetadata = ((vmMetadata vm) { vmCheckParams = psb }) } in
  (isRight $ viewMarkerMismatch vma vmb) === False


prop_validateViewMarkers_same :: Property
prop_validateViewMarkers_same = forAll ((,) <$> passedViewMarker <*> choose (1, 100)) $ \(vm, n) ->
  let vms = NE.fromList . take n $ repeat vm in
  (validateViewMarkers vms) === (Right ())

prop_validateViewMarkers_failed :: NonEmpty ViewMarker -> Property
prop_validateViewMarkers_failed vms = forAll (fmap NE.fromList $ listOf1 failedViewMarker) $ \fvms ->
  let vms1 = vms <> fvms
      vms2 = fvms <> vms in
  (isLeft (validateViewMarkers vms1), isLeft (validateViewMarkers vms2)) === (True, True)

prop_compatibleEntries_text :: ObservationCount -> Property
prop_compatibleEntries_text oc = forAll (elements muppets) $ \t ->
  let l = parseField t
      csText = compatibleEntries TextField l oc
      csIntegral = compatibleEntries IntegralField l oc
      csReal = compatibleEntries RealField l oc
      csBoolean = compatibleEntries BooleanField l oc in
  (csText, csIntegral, csReal, csBoolean) === (CompatibleEntries (unObservationCount oc), CompatibleEntries 0, CompatibleEntries 0, CompatibleEntries 0)

prop_compatibleEntries_integral :: ObservationCount -> Int -> Property
prop_compatibleEntries_integral oc n =
  let l = parseField . T.pack $ show n
      csText = compatibleEntries TextField l oc
      csIntegral = compatibleEntries IntegralField l oc
      csReal = compatibleEntries RealField l oc
      csBoolean = compatibleEntries BooleanField l oc in
  (csText, csIntegral, csReal, csBoolean) === (CompatibleEntries (unObservationCount oc), CompatibleEntries (unObservationCount oc), CompatibleEntries (unObservationCount oc), CompatibleEntries 0)

prop_compatibleEntries_boolean :: ObservationCount -> Property
prop_compatibleEntries_boolean oc = forAll renderedBool $ \b ->
  let l = parseField b
      csText = compatibleEntries TextField l oc
      csIntegral = compatibleEntries IntegralField l oc
      csReal = compatibleEntries RealField l oc
      csBoolean = compatibleEntries BooleanField l oc in
  (csText, csIntegral, csReal, csBoolean) === (CompatibleEntries (unObservationCount oc), CompatibleEntries 0, CompatibleEntries 0, CompatibleEntries (unObservationCount oc))

prop_compatibleEntries_real :: ObservationCount -> Double -> Property
prop_compatibleEntries_real oc n =
  let l = parseField . T.pack $ show n
      csText = compatibleEntries TextField l oc
      csIntegral = compatibleEntries IntegralField l oc
      csReal = compatibleEntries RealField l oc
      csBoolean = compatibleEntries BooleanField l oc in
  (csText, csIntegral, csReal, csBoolean) === (CompatibleEntries (unObservationCount oc), CompatibleEntries 0, CompatibleEntries (unObservationCount oc), CompatibleEntries 0)

prop_compatibleEntries_empty :: ObservationCount -> Property
prop_compatibleEntries_empty oc =
  let l = parseField ""
      csText = compatibleEntries TextField l oc
      csIntegral = compatibleEntries IntegralField l oc
      csReal = compatibleEntries RealField l oc
      csBoolean = compatibleEntries BooleanField l oc in
  (csText, csIntegral, csReal, csBoolean) === (CompatibleEntries (unObservationCount oc), CompatibleEntries (unObservationCount oc), CompatibleEntries (unObservationCount oc), CompatibleEntries (unObservationCount oc))

prop_normalizeFieldHistogram :: FieldHistogram -> Property
prop_normalizeFieldHistogram h =
  forAll (fmap (RowCount . getLarge) $ arbitrary `suchThat` ((>= histogramMax) . RowCount . getLarge)) $ \rc ->
    let normed = normalizeFieldHistogram rc h in
    case normed of
      Left e ->
        failWith $ renderInferenceError e
      Right normed' -> 
        (VU.all (>= 0.0) normed', VU.all (<= 1.0) normed') === (True, True)
  where
    histogramMax = RowCount . unCompatibleEntries . VU.maximum $ unFieldHistogram h

prop_fieldCandidates :: FieldMatchRatio -> Property
prop_fieldCandidates fmr = forAll validHistogramPair $ \(rc, h) ->  case fieldCandidates fmr rc h of
    Left e ->
      failWith $ renderInferenceError e
    Right cands ->
      S.member TextField cands === True

prop_fieldCandidates_real :: FieldMatchRatio -> Property
prop_fieldCandidates_real fmr = forAll realHistogramPair $ \(rc, h) -> case fieldCandidates fmr rc h of
  Left e ->
    failWith $ renderInferenceError e
  Right cands ->
    S.member RealField cands === True

prop_fieldCandidates_boolean :: FieldMatchRatio -> Property
prop_fieldCandidates_boolean fmr = forAll booleanHistogramPair $ \(rc, h) -> case fieldCandidates fmr rc h of
  Left e ->
    failWith $ renderInferenceError e
  Right cands ->
    S.member BooleanField cands === True

return []
tests :: IO Bool
tests = $quickCheckAll