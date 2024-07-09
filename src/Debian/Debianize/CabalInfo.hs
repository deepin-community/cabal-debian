{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}
module Debian.Debianize.CabalInfo
    ( -- * Types
      CabalInfo
    , PackageInfo(PackageInfo, cabalName, devDeb, docDeb, profDeb)
      -- * Lenses
    , packageDescription
    , debInfo
    , debianNameMap
    , epochMap
    , packageInfo
      -- * Builder
    , newCabalInfo
    ) where

import Control.Lens
import Control.Monad.Catch (MonadMask)
import Control.Monad.State (execStateT)
import Control.Monad.Trans (MonadIO, liftIO)
import Data.Generics (Data, Typeable)
import Data.Map as Map (Map)
import Data.Text as Text (null, pack, strip)
import Debian.Debianize.BasicInfo (Flags)
import Debian.Debianize.DebInfo as D (control, copyright, DebInfo, makeDebInfo)
import Debian.Debianize.BinaryDebDescription (Canonical(canonical))
import Debian.Debianize.CopyrightDescription (defaultCopyrightDescription)
import Debian.Debianize.InputCabal (inputCabalization)
import Debian.Debianize.SourceDebDescription as S (homepage)
import Debian.Debianize.VersionSplits (VersionSplits)
import Debian.Orphans ()
import Debian.Relation (BinPkgName)
import Debian.Version (DebianVersion)
import Distribution.Package (PackageName)
import Distribution.PackageDescription as Cabal (PackageDescription(homepage))
#if MIN_VERSION_Cabal(3,2,0)
import qualified Distribution.Utils.ShortText as ST
#endif
import Prelude hiding (init, init, log, log, null)

-- | Bits and pieces of information about the mapping from cabal package
-- names and versions to debian package names and versions.  In essence,
-- an 'Atoms' value represents a package's debianization.  The lenses in
-- this module are used to get and set the values hidden in this Atoms
-- value.  Many of the values should be left alone to be set when the
-- debianization is finalized.
data CabalInfo
    = CabalInfo
      { _packageDescription :: PackageDescription
      -- ^ The result of reading a cabal configuration file.
      , _debInfo :: DebInfo
      -- ^ Information required to represent a non-cabal debianization.
      , _debianNameMap :: Map PackageName VersionSplits
      -- ^ Mapping from cabal package name and version to debian source
      -- package name.  This allows different ranges of cabal versions to
      -- map to different debian source package names.
      , _epochMap :: Map PackageName Int
      -- ^ Specify epoch numbers for the debian package generated from a
      -- cabal package.  Example: @EpochMapping (PackageName "HTTP") 1@.
      , _packageInfo :: Map PackageName PackageInfo
      -- ^ Supply some info about a cabal package.
      } deriving (Show, Data, Typeable)

data PackageInfo = PackageInfo { cabalName :: PackageName
                               , devDeb :: Maybe (BinPkgName, DebianVersion)
                               , profDeb :: Maybe (BinPkgName, DebianVersion)
                               , docDeb :: Maybe (BinPkgName, DebianVersion) } deriving (Eq, Ord, Show, Data, Typeable)

$(makeLenses ''CabalInfo)

instance Canonical CabalInfo where
    canonical x = x {_debInfo = canonical (_debInfo x)}

-- | Given the 'Flags' value read the cabalization and build a new
-- 'CabalInfo' record.
newCabalInfo :: (MonadIO m, MonadMask m{-, Functor m-}) => Flags -> m (Either String CabalInfo)
newCabalInfo flags' =
    inputCabalization flags' >>= either (return . Left) (\p -> Right <$> doPkgDesc p)
    where
      doPkgDesc pkgDesc = do
        copyrt <- liftIO $ defaultCopyrightDescription pkgDesc
        execStateT
          (do (debInfo . copyright) .= Just copyrt
              (debInfo . control . S.homepage) .= case strip (toText (Cabal.homepage pkgDesc)) of
                                                    x | Text.null x -> Nothing
                                                    x -> Just x)
          (makeCabalInfo flags' pkgDesc)
#if MIN_VERSION_Cabal(3,2,0)
      toText = pack . ST.fromShortText
#else
      toText = pack
#endif

makeCabalInfo :: Flags -> PackageDescription -> CabalInfo
makeCabalInfo fs pkgDesc =
    CabalInfo
      { _packageDescription = pkgDesc
      , _epochMap = mempty
      , _packageInfo = mempty
      , _debianNameMap = mempty
      , _debInfo = makeDebInfo fs
      }
