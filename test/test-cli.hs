import           Disorder.Core.Main

main :: IO ()
main =
  disorderCliMain [
      "./dist/build/warden/warden"
    , "./dist/build/warden-gen/warden-gen"
    , "./dist/build/warden-sample/warden-sample"
    ]
