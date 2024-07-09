-- | How to name the debian packages based on the cabal package name and version number.
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, OverloadedStrings, RankNTypes, ScopedTypeVariables, StandaloneDeriving, TypeFamilies #-}
{-# OPTIONS -Wall -Wwarn -fno-warn-name-shadowing -fno-warn-orphans #-}
module Debian.Debianize.DebianName
    ( debianName
    , debianNameBase
    , mkPkgName
    , mkPkgName'
    , mapCabal
    , splitCabal
    , remapCabal
    ) where


import Control.Lens
import Data.Char (toLower)
import Data.Map as Map (alter, lookup)
import Debian.Debianize.Monad (CabalT)
import Debian.Debianize.CabalInfo as A (debianNameMap, packageDescription, debInfo)
import Debian.Debianize.BinaryDebDescription as Debian (PackageType(..))
import Debian.Debianize.DebInfo as D (overrideDebianNameBase, utilsPackageNameBase)
import Debian.Debianize.VersionSplits (DebBase(DebBase, unDebBase), doSplits, insertSplit, makePackage, VersionSplits(oldestPackage, splits))
import Debian.Orphans ()
import Debian.Relation (PkgName(..), Relations)
import qualified Debian.Relation as D (VersionReq(EEQ))
import Debian.Version (parseDebianVersion')
import Distribution.Compiler (CompilerFlavor(..))
import Distribution.Package (Dependency(..), PackageIdentifier(..), PackageName, unPackageName)
import Distribution.Version (Version)
import qualified Distribution.PackageDescription as Cabal (PackageDescription(package))
import Distribution.Pretty (prettyShow)
import Prelude hiding (unlines)

data Dependency_
  = BuildDepends Dependency
  | BuildTools Dependency
  | PkgConfigDepends Dependency
  | ExtraLibs Relations
    deriving (Eq, Show)

-- | Build the Debian package name for a given package type.
debianName :: (Monad m, PkgName name) => PackageType -> CompilerFlavor -> CabalT m name
debianName typ hc =
    do base <-
           case (typ, hc) of
             (Utilities, GHC) -> use (debInfo . utilsPackageNameBase) >>= maybe (((\ base -> "haskell-" ++ base ++ "-utils") . unDebBase) <$> debianNameBase) return
             (Utilities, _) -> use (debInfo . utilsPackageNameBase) >>= maybe (((\ base -> base ++ "-utils") . unDebBase) <$> debianNameBase) return
             _ -> unDebBase <$> debianNameBase
       return $ mkPkgName' hc typ (DebBase base)

-- | Function that applies the mapping from cabal names to debian
-- names based on version numbers.  If a version split happens at v,
-- this will return the ltName if < v, and the geName if the relation
-- is >= v.
debianNameBase :: Monad m => CabalT m DebBase
debianNameBase =
    do nameBase <- use (debInfo . D.overrideDebianNameBase)
       pkgDesc <- use packageDescription
       let pkgId = Cabal.package pkgDesc
       nameMap <- use A.debianNameMap
       let pname = pkgName pkgId
           version = (Just (D.EEQ (parseDebianVersion' (prettyShow (pkgVersion pkgId)))))
       case (nameBase, Map.lookup (pkgName pkgId) nameMap) of
         (Just base, _) -> return base
         (Nothing, Nothing) -> return $ debianBaseName pname
         (Nothing, Just splits) -> return $ doSplits splits version

-- | Build a debian package name from a cabal package name and a
-- debian package type.  Unfortunately, this does not enforce the
-- correspondence between the PackageType value and the name type, so
-- it can return nonsense like (SrcPkgName "libghc-debian-dev").
mkPkgName :: PkgName name => CompilerFlavor -> PackageName -> PackageType -> name
mkPkgName hc pkg typ = mkPkgName' hc typ (debianBaseName pkg)

mkPkgName' :: PkgName name => CompilerFlavor -> PackageType -> DebBase -> name
mkPkgName' hc typ (DebBase base) =
    pkgNameFromString $
             case typ of
                Documentation -> prefix ++ base ++ "-doc"
                Development -> prefix ++ base ++ "-dev"
                Profiling -> prefix ++ base ++ "-prof"
                Utilities -> base {- ++ case hc of
                                          GHC -> ""
                                          _ -> "-" ++ map toLower (show hc) -}
                Exec -> base
                Source -> base
                HaskellSource -> "haskell-" ++ base
                Cabal -> base
    where prefix = "lib" ++ map toLower (show hc) ++ "-"

debianBaseName :: PackageName -> DebBase
debianBaseName p =
    DebBase (map (fixChar . toLower) (unPackageName p))
    where
      -- Underscore is prohibited in debian package names.
      fixChar :: Char -> Char
      fixChar '_' = '-'
      fixChar c = toLower c

-- | Map all versions of Cabal package pname to Debian package dname.
-- Not really a debian package name, but the name of a cabal package
-- that maps to the debian package name we want.  (Should this be a
-- SrcPkgName?)
mapCabal :: Monad m => PackageName -> DebBase -> CabalT m ()
mapCabal pname dname =
    debianNameMap %= Map.alter f pname
    where
      f :: Maybe VersionSplits -> Maybe VersionSplits
      f Nothing = Just (makePackage dname)
      f (Just sp) | any (== dname) (oldestPackage sp : map snd (splits sp)) = Just sp
      f (Just sp) = error $ "mapCabal " ++ show pname ++ " " ++ show dname ++ ": - already mapped: " ++ show sp

-- | Map versions less than ver of Cabal Package pname to Debian package ltname
splitCabal :: Monad m => PackageName -> DebBase -> Version -> CabalT m ()
splitCabal pname ltname ver =
    debianNameMap %= Map.alter f pname
    where
      f :: Maybe VersionSplits -> Maybe VersionSplits
      f Nothing = error $ "splitCabal - not mapped: " ++ show pname
      f (Just sp) = Just (insertSplit ver ltname sp)

-- | Replace any existing mapping of the cabal name 'pname' with the
-- debian name 'dname'.  (Use case: to change the debian package name
-- so it differs from the package provided by ghc.)
remapCabal :: Monad m => PackageName -> DebBase -> CabalT m ()
remapCabal pname dname = do
  debianNameMap %= Map.alter (const Nothing) pname
  mapCabal pname dname
