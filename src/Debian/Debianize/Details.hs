-- | Detailed information about the specific repositories such as
-- debian or seereason - in particular how cabal names are mapped to
-- debian.
{-# LANGUAGE CPP #-}
{-# OPTIONS -Wall #-}
module Debian.Debianize.Details
    ( debianDefaults
    ) where

import Control.Lens
import Data.Map as Map (insert)
import Debian.Debianize.DebianName (mapCabal, splitCabal)
import Debian.Debianize.Monad (CabalT)
import Debian.Debianize.CabalInfo as A (epochMap, debInfo)
import Debian.Debianize.DebInfo as D (execMap)
import Debian.Debianize.VersionSplits (DebBase(DebBase))
import Debian.Relation (BinPkgName(BinPkgName), Relation(Rel))
import Distribution.Package (mkPackageName)
import Distribution.Version (mkVersion)

-- | Update the CabalInfo value in the CabalT state with some details about
-- the debian repository - special cases for how some cabal packages
-- are mapped to debian package names.
debianDefaults :: Monad m => CabalT m ()
debianDefaults =
    do -- These are the two epoch names I know about in the debian repo
       A.epochMap %= Map.insert (mkPackageName "HaXml") 1
       A.epochMap %= Map.insert (mkPackageName "HTTP") 1
       -- Associate some build tools and their corresponding
       -- (eponymous) debian package names
       mapM_ (\name -> (A.debInfo . D.execMap) %= Map.insert name [[Rel (BinPkgName name) Nothing Nothing]])
            ["alex", "c2hs", "ghc", "happy", "hsx2hs"]
       mapCabal (mkPackageName "QuickCheck") (DebBase "quickcheck2")
       -- Something was required for this package at one time - it
       -- looks like a no-op now
       mapCabal (mkPackageName "gtk2hs-buildtools") (DebBase "gtk2hs-buildtools")
       mapCabal (mkPackageName "haskell-src-exts") (DebBase "src-exts")
       mapCabal (mkPackageName "haskell-src-exts-simple") (DebBase "src-exts-simple")
       mapCabal (mkPackageName "haskell-src-exts-util") (DebBase "src-exts-util")
       mapCabal (mkPackageName "haskell-src-meta") (DebBase "src-meta")
       mapCabal (mkPackageName "Cabal") (DebBase "cabal")

       mapCabal (mkPackageName "happstack-authenticate") (DebBase "happstack-authenticate")
       splitCabal (mkPackageName "happstack-authenticate") (DebBase "happstack-authenticate-0") (mkVersion [2])
