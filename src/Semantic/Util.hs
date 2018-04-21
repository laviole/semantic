-- MonoLocalBinds is to silence a warning about a simplifiable constraint.
{-# LANGUAGE DataKinds, MonoLocalBinds, ScopedTypeVariables, TypeFamilies, TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}
module Semantic.Util where

import Analysis.Abstract.BadVariables
import Analysis.Abstract.BadModuleResolutions
import Analysis.Abstract.BadValues
import Analysis.Abstract.Caching
import Analysis.Abstract.Quiet
import Analysis.Abstract.Dead
import Analysis.Abstract.Evaluating as X
import Analysis.Abstract.ImportGraph
import Analysis.Abstract.Tracing
import Analysis.Declaration
import Control.Abstract.Analysis
import Control.Monad.IO.Class
import Data.Abstract.Evaluatable hiding (head)
import Data.Abstract.Address
import Data.Abstract.Located
import Data.Abstract.Module
import Data.Abstract.Package as Package
import Data.Abstract.Type
import Data.Abstract.Value
import Data.Blob
import Data.File
import Data.Diff
import Data.Range
import Data.Record
import Data.Span
import Data.Term
import Diffing.Algorithm
import Diffing.Interpreter
import System.FilePath.Glob
import qualified GHC.TypeLits as TypeLevel
import Language.Preluded
import Parsing.Parser
import Prologue
import Semantic.Diff (diffTermPair)
import Semantic.IO as IO
import Semantic.Task
import Semantic.Graph
import qualified Semantic.Task as Task
import System.FilePath.Posix

import qualified Language.Go.Assignment as Go
import qualified Language.Python.Assignment as Python
import qualified Language.Ruby.Assignment as Ruby
import qualified Language.PHP.Assignment as PHP
import qualified Language.TypeScript.Assignment as TypeScript

-- -- Ruby
-- evalRubyProject = runEvaluatingWithPrelude rubyParser ["rb"]
-- evalRubyFile path = runEvaluating <$> (withPrelude <$> parsePrelude rubyParser <*> (evaluateModule <$> parseFile rubyParser Nothing path))
--
-- evalRubyProjectGraph path = runAnalysis @(ImportGraphing (BadModuleResolutions (BadVariables (BadValues (Quietly (Evaluating (Located Precise Ruby.Term) Ruby.Term (Value (Located Precise Ruby.Term)))))))) <$> (withPrelude <$> parsePrelude rubyParser <*> (evaluatePackageBody <$> parseProject rubyParser ["rb"] path))
--
-- evalRubyImportGraph paths = runAnalysis @(ImportGraphing (Evaluating (Located Precise Ruby.Term) Ruby.Term (Value (Located Precise Ruby.Term)))) . evaluateModules <$> parseFiles rubyParser (dropFileName (head paths)) paths
--
-- evalRubyBadVariables paths = runAnalysis @(BadVariables (Evaluating Precise Ruby.Term (Value Precise))) . evaluateModules <$> parseFiles rubyParser (dropFileName (head paths)) paths
--
-- -- Go
-- evalGoProject path = runEvaluating . evaluatePackageBody <$> parseProject goParser ["go"] path
-- evalGoFile path = runEvaluating . evaluateModule <$> parseFile goParser Nothing path
--
-- typecheckGoFile path = runAnalysis @(Caching (Evaluating Monovariant Go.Term Type)) . evaluateModule <$> parseFile goParser Nothing path
--
-- -- Python
-- evalPythonProject = runEvaluatingWithPrelude pythonParser ["py"]
-- evalPythonFile path = runEvaluating <$> (withPrelude <$> parsePrelude pythonParser <*> (evaluateModule <$> parseFile pythonParser Nothing path))
-- evalPythonProjectGraph path = runAnalysis @(ImportGraphing (BadModuleResolutions (BadVariables (BadValues (Quietly (Evaluating (Located Precise Python.Term) Python.Term (Value (Located Precise Python.Term)))))))) <$> (withPrelude <$> parsePrelude pythonParser <*> (evaluatePackageBody <$> parseProject pythonParser ["py"] path))
--
-- typecheckPythonFile path = runAnalysis @(Caching (Evaluating Monovariant Python.Term Type)) . evaluateModule <$> parseFile pythonParser Nothing path
-- tracePythonFile path = runAnalysis @(Tracing [] (Evaluating Precise Python.Term (Value Precise))) . evaluateModule <$> parseFile pythonParser Nothing path
-- evalDeadTracePythonFile path = runAnalysis @(DeadCode (Tracing [] (Evaluating Precise Python.Term (Value Precise)))) . evaluateModule <$> parseFile pythonParser Nothing path
--
-- -- PHP
-- evalPHPProject path = runEvaluating . evaluatePackageBody <$> parseProject phpParser ["php"] path
-- evalPHPFile path = runEvaluating . evaluateModule <$> parseFile phpParser Nothing path
--
-- -- TypeScript
-- evalTypeScriptProject path = runEvaluating . evaluatePackageBody <$> parseProject typescriptParser ["ts", "tsx"] path
-- evalTypeScriptFile path = runEvaluating . evaluateModule <$> parseFile typescriptParser Nothing path
-- typecheckTypeScriptFile path = runAnalysis @(Caching (Evaluating Monovariant TypeScript.Term Type)) . evaluateModule <$> parseFile typescriptParser Nothing path

-- JavaScript
-- evalJavaScriptProject path = runAnalysis @(EvaluatingWithHoles TypeScript.Term) . evaluatePackageBody <$> parseProject typescriptParser ["js"] path
-- evalJavaScriptProject path = parsePackage Nothing typescriptParser (takeDirectory path)

-- runEvaluatingWithPrelude parser exts path = runEvaluating <$> (withPrelude <$> parsePrelude parser <*> (evaluatePackageBody <$> parseProject parser exts path))

evalGoProject path = runAnalysis @(JustEvaluating Go.Term) <$> evaluateProject goParser path
evalRubyProject path = runAnalysis @(TestEvaluating Ruby.Term) <$> evaluateProject rubyParser path
evalPHPProject path = runAnalysis @(JustEvaluating PHP.Term) <$> evaluateProject phpParser path
evalPythonProject path = runAnalysis @(JustEvaluating Python.Term) <$> evaluateProject pythonParser path
evalTypeScriptProject path = runAnalysis @(EvaluatingWithHoles TypeScript.Term) <$> evaluateProject typescriptParser path
evaluateProject parser path = evaluatePackage <$> runTask (readProject Nothing (file path :| []) >>= parsePackage parser Nothing)
-- evaluateProject path = evaluatePackage <$> runTask (do
--   project <- readProject Nothing (file path :| [])
--   case someAnalysisParser (Proxy :: Proxy '[ Evaluatable, Declarations1, FreeVariables1, Functor, Eq1, Ord1, Show1 ]) <$> projectLanguage project of
--     Just (SomeAnalysisParser parser prelude) -> parsePackage parser prelude project
--     Nothing -> undefined)


-- evalJavaScriptProject = evalProject @(JustEvaluating TypeScript.Term)

-- evalProject :: forall term effects a.
--                ( Members '[Exc SomeException, Task] effects
--                , Members (EvaluatingEffects (Located Precise term) term (Value (Located Precise term))) effects
--                )
-- evalProject :: FilePath ->  IO (Final effs (JustEvaluating term effects a))
-- evalProject :: forall effs a. FilePath -> IO (Final effs a)
-- evalProject :: forall m location term value effects. ( MonadAnalysis location term value m, Members (EvaluatingEffects location term value) effects )
--             => FilePath -> IO (Final effects value)
-- evalProject path = runTask $ do
--   project <- readProject Nothing (file path :| [])
--   case someAnalysisParser (Proxy :: Proxy '[ Evaluatable, Declarations1, FreeVariables1, Functor, Eq1, Ord1, Show1 ]) <$> projectLanguage project of
--     Just (SomeAnalysisParser parser prelude) -> do
--       package <- parsePackage typescriptParser prelude project
--       analyze (SomeAnalysis (evaluatePackage @(JustEvaluating TypeScript.Term) package))
--     Nothing -> Task.throwError (SomeException (NoLanguageForBlob (filePath (projectEntryPoint project))))
--
--
  -- package <- parsePackage typescriptParser project prelude
  -- runAnalysis @(EvaluatingWithHoles TypeScript.Term) package


type TestEvaluating term = Evaluating Precise term (Value Precise)
type JustEvaluating term = Evaluating (Located Precise term) term (Value (Located Precise term))
type EvaluatingWithHoles term = BadModuleResolutions (BadVariables (BadValues (Quietly (Evaluating (Located Precise term) term (Value (Located Precise term))))))
type ImportGraphingWithHoles term = ImportGraphing (EvaluatingWithHoles term)


-- -- TODO: Remove this by exporting EvaluatingEffects
-- runEvaluating :: forall term effects a.
--                  ( Effects Precise term (Value Precise) (Evaluating Precise term (Value Precise) effects) ~ effects
--                  , Corecursive term
--                  , Recursive term )
--               => Evaluating Precise term (Value Precise) effects a
--               -> Final effects a
-- runEvaluating = runAnalysis @(Evaluating Precise term (Value Precise))
--
-- parsePrelude :: forall term. TypeLevel.KnownSymbol (PreludePath term) => Parser term -> IO (Module term)
-- parsePrelude parser = do
--   let preludePath = TypeLevel.symbolVal (Proxy :: Proxy (PreludePath term))
--   parseFile parser Nothing preludePath

-- parseProject :: Parser term
--                 -> [Prelude.String]
--                 -> FilePath
--                 -> IO (PackageBody term)
-- parseProject parser exts entryPoint = do
--   let rootDir = takeDirectory entryPoint
--   paths <- getPaths exts rootDir
--   modules <- parseFiles parser rootDir paths
--   pure $ fromModulesWithEntryPoint modules (takeFileName entryPoint)
--
-- withPrelude prelude a = do
--   preludeEnv <- evaluateModule prelude *> getEnv
--   withDefaultEnvironment preludeEnv a
--
-- getPaths exts = fmap fold . globDir (compile . mappend "**/*." <$> exts)
--

-- Read and parse a file.
parseFile :: Parser term -> Maybe FilePath -> FilePath -> IO (Module term)
parseFile parser rootDir path = runTask $ do
  blob <- readBlob (file path)
  moduleForBlob rootDir blob <$> parse parser blob

-- parseFiles :: Parser term -> FilePath -> [FilePath] -> IO [Module term]
-- parseFiles parser rootDir = traverse (parseFile parser (Just rootDir))

-- parsePackage :: PackageName -> Parser term -> FilePath -> [FilePath] -> IO (Package term)
-- parsePackage name parser rootDir = runTask . Task.parsePackage name parser rootDir


-- Read a file from the filesystem into a Blob.
-- readBlob :: MonadIO m => FilePath -> m Blob
-- readBlob path = fromJust <$> IO.readFile (file path)

-- Diff helpers
diffWithParser :: ( HasField fields Data.Span.Span
                  , HasField fields Range
                  , Eq1 syntax
                  , Show1 syntax
                  , Traversable syntax
                  , Diffable syntax
                  , GAlign syntax
                  , HasDeclaration syntax
                  , Members '[Distribute WrappedTask, Task] effs
                  )
               => Parser (Term syntax (Record fields))
               -> BlobPair
               -> Eff effs (Diff syntax (Record (Maybe Declaration ': fields)) (Record (Maybe Declaration ': fields)))
diffWithParser parser blobs = distributeFor blobs (\ blob -> WrapTask $ parse parser blob >>= decorate (declarationAlgebra blob)) >>= diffTermPair diffTerms . runJoin
