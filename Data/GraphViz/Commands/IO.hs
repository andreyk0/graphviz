{- |
   Module      : Data.GraphViz.Commands.IO
   Description : IO-related functions for graphviz.
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   Various utility functions to help with custom I\/O of Dot code.
-}
module Data.GraphViz.Commands.IO
       ( -- * Encoding
         -- $encoding
         toUTF8
         -- * Operations on files
       , writeDotFile
       , readDotFile
         -- * Operations on handles
       , hPutDot
       , hPutCompactDot
       , hGetDot
       , hGetStrict
         -- * Special cases for standard input and output
       , putDot
       , readDot
         -- * Running external commands
       , runCommand
       ) where

import Data.GraphViz.State(initialState)
import Data.GraphViz.Types(DotRepr, printDotGraph, parseDotGraph)
import Data.GraphViz.Printing(toDot)
import Data.GraphViz.Exception
import Text.PrettyPrint.Leijen.Text(displayT, renderCompact)

import qualified Data.Text.Lazy.Encoding as T
import Data.Text.Encoding.Error(UnicodeException(DecodeError))
import Data.Text.Lazy(Text)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as B
import Data.ByteString.Lazy(ByteString)
import Control.Monad(liftM)
import Control.Monad.Trans.State
import System.IO(Handle, IOMode(ReadMode,WriteMode)
                , withFile, stdout, stdin, hPutChar
                , hClose, hGetContents, hSetBinaryMode)
import System.Exit(ExitCode(ExitSuccess))
import System.Process(runInteractiveProcess, waitForProcess)
import Control.Exception.Extensible(IOException, evaluate)
import Control.Concurrent(MVar, forkIO, newEmptyMVar, putMVar, takeMVar)

-- -----------------------------------------------------------------------------

-- | Correctly render Graphviz output in a more machine-oriented form
--   (i.e. more compact than the output of 'renderDot').
renderCompactDot :: (DotRepr dg n) => dg n -> Text
renderCompactDot = displayT . renderCompact
                   . flip evalState initialState
                   . toDot

-- -----------------------------------------------------------------------------
-- Encoding

{- $encoding
  By default, Dot code should be in UTF-8.  However, by usage of the
  /charset/ attribute, users are able to specify that the ISO-8859-1
  (aka Latin1) encoding should be used instead:
  <http://www.graphviz.org/doc/info/attrs.html#d:charset>

  To simplify matters, graphviz does /not/ work with ISO-8859-1.  If
  you wish to deal with existing Dot code that uses this encoding, you
  will need to manually read that file in to a 'Text' value.

  If a file uses a non-UTF-8 encoding, then a 'GraphvizException' will
  be thrown.
-}

-- | Read a UTF-8 encoded (lazy) 'ByteString', throwing a
--   'GraphvizException' if there is a decoding error.
toUTF8 :: ByteString -> Text
toUTF8 = mapException (\e@DecodeError{} -> NotUTF8Dot $ show e)
         . T.decodeUtf8

-- -----------------------------------------------------------------------------
-- Output

hPutDot :: (DotRepr dg n) => Handle -> dg n -> IO ()
hPutDot = toHandle printDotGraph

hPutCompactDot :: (DotRepr dg n) => Handle -> dg n -> IO ()
hPutCompactDot = toHandle renderCompactDot

toHandle        :: (DotRepr dg n) => (dg n -> Text) -> Handle -> dg n
                   -> IO ()
toHandle f h dg = do B.hPutStr h . T.encodeUtf8 $ f dg
                     hPutChar h '\n'

-- | Strictly read in a 'Text' value using an appropriate encoding.
hGetStrict :: Handle -> IO Text
hGetStrict = liftM (toUTF8 . B.fromChunks . (:[]))
             . SB.hGetContents

hGetDot :: (DotRepr dg n) => Handle -> IO (dg n)
hGetDot = liftM parseDotGraph . hGetStrict

writeDotFile   :: (DotRepr dg n) => FilePath -> dg n -> IO ()
writeDotFile f = withFile f WriteMode . flip hPutDot

readDotFile   :: (DotRepr dg n) => FilePath -> IO (dg n)
readDotFile f = withFile f ReadMode hGetDot

putDot :: (DotRepr dg n) => dg n -> IO ()
putDot = hPutDot stdout

readDot :: (DotRepr dg n) => IO (dg n)
readDot = hGetDot stdin

-- -----------------------------------------------------------------------------

-- | Run an external command on the specified 'DotRepr'.
--
--   If the command was unsuccessful, then a 'GraphvizException' is
--   thrown.
runCommand :: (DotRepr dg n)
              => String           -- ^ Command to run
              -> [String]         -- ^ Command-line arguments
              -> (Handle -> IO a) -- ^ Obtaining the output
              -> dg n
              -> IO a
runCommand cmd args hf dg
  = mapException notRunnable
    $ bracket
        (runInteractiveProcess cmd args Nothing Nothing)
        (\(inh,outh,errh,_) -> hClose inh >> hClose outh >> hClose errh)
        $ \(inp,outp,errp,prc) -> do

          -- The input and error are text, not binary
          hSetBinaryMode inp True
          hSetBinaryMode errp False

          -- Make sure we close the input or it will hang!!!!!!!
          forkIO $ hPutCompactDot inp dg >> hClose inp

          -- Need to make sure both the output and error handles are
          -- really fully consumed.
          mvOutput <- newEmptyMVar
          mvErr    <- newEmptyMVar

          forkIO $ signalWhenDone hGetContents' errp mvErr
          forkIO $ signalWhenDone hf' outp mvOutput

          -- When these are both able to be taken, then the forks are finished
          err <- takeMVar mvErr
          output <- takeMVar mvOutput

          exitCode <- waitForProcess prc

          case exitCode of
            ExitSuccess -> return output
            _           -> throw . GVProgramExc $ othErr ++ err
    where
      notRunnable :: IOException -> GraphvizException
      notRunnable e = GVProgramExc $ unwords
                      [ "Unable to call the Graphviz command "
                      , cmd
                      , " with the arguments: "
                      , unwords args
                      , " because of: "
                      , show e
                      ]

      -- Augmenting the hf function to let it work within the forkIO:
      hf' = mapException fErr . hf
      fErr :: IOException -> GraphvizException
      fErr e = GVProgramExc $ "Error re-directing the output from "
               ++ cmd ++ ": " ++ show e

      othErr = "Error messages from " ++ cmd ++ ":\n"

-- -----------------------------------------------------------------------------
-- Utility functions

-- | A version of 'hGetContents' that fully evaluates the contents of
--   the 'Handle' (that is, until EOF is reached).  The 'Handle' is
--   not closed.
hGetContents'   :: Handle -> IO String
hGetContents' h = do r <- hGetContents h
                     evaluate $ length r
                     return r

-- | Store the result of the 'Handle' consumption into the 'MVar'.
signalWhenDone        :: (Handle -> IO a) -> Handle -> MVar a -> IO ()
signalWhenDone f h mv = f h >>= putMVar mv >> return ()
