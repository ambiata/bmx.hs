{-| The collection of builtin helpers, included in the default environment.
    Helpers here should be compatible with Handlebars.
 -}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module BMX.Builtin.Helpers where

import           Data.List (zipWith)
import           Data.Text (Text)
import qualified Data.Text as T

import           BMX.Function

import           P hiding (log, unless)

-- | The default collection of builtins.
builtinHelpers :: (Applicative m, Monad m) => [(Text, Helper m)]
builtinHelpers = [
    ("noop", noop)
  , ("if", iff)
  , ("unless", unless)
  , ("with", with)
  , ("lookup", lookup)
  , ("each", each)
  ]

-- | The "noop" block helper. Renders the main block.
noop :: (Applicative m, Monad m) => Helper m
noop = blockHelper $ \b _ -> liftBMX (eval b)

-- | The "if" block helper. Renders the main block if the argument is truthy.
-- Otherwise, it renders the inverse block.
iff :: (Applicative m, Monad m) => Helper m
iff = blockHelper $ \thenp elsep -> do
  v <- value
  liftBMX $ if truthy v then eval thenp else eval elsep

-- | The "unless" block helper. The opposite of "if".
unless :: (Applicative m, Monad m) => Helper m
unless = blockHelper $ \thenp elsep -> do
  v <- value
  liftBMX $ if truthy v then eval elsep else eval thenp

-- | The "with" block helper. Accept a Context as argument.
with :: (Applicative m, Monad m) => Helper m
with = blockHelper $ \thenp elsep -> do
  ctx <- optional context
  liftBMX $ maybe
    (eval elsep)
    (\c -> withContext c (eval thenp))
    ctx

-- | The "lookup" helper. Takes a context and a string, and looks up a
-- value in a context. Returns @undefined@ when it doesn't exist.
lookup :: (Applicative m, Monad m) => Helper m
lookup = helper $ do
  ctx <- context
  str <- string
  liftBMX $ do
    mv <- withContext ctx (lookupValue str)
    return (fromMaybe UndefinedV mv)

-- | The "each" helper. Takes an iterable value (a context or a list),
-- and renders the main block for each item in the collection.
-- If the collection is empty, it renders the inverse block instead.
--
-- The special variables @first, @last, @key, @index, and this are registered
-- during the loop. These are as defined in Handlebars.
--
-- If block parameters are supplied, we also bind the first parameter to the
-- value in each loop, and the second parameter to the loop index.
each :: (Applicative m, Monad m) => Helper m
each = blockHelper $ \thenp elsep -> do
  iter <- eitherA list context
  par1 <- optional param -- block param: name for current item (list), name for key (ctx)
  par2 <- optional param -- block param: name for current loop idx (list), name for val (ctx)
  -- This code is the worst, mostly because of special variables.
  let go = if null loop then eval elsep else fmap fold . sequence $ loop
      loop = either eachList eachMap iter
      -- Separate iteration cases for context and list
      eachMap c = indices 0 (fmap stepKV (contextToList c))
      eachList l = zipWith listIdx ([0..] :: [Integer]) (indices 0 (fmap step l))
      -- Apply indices, first and last markers to each action
      indices 0 (k:[]) = [(index 0 . frst . last) k]
      indices 0 (k:ks@(_:_)) = index 0 (frst k) : indices 1 ks
      indices n (k:ks@(_:_)) = index n k : indices (n + 1) ks
      indices n (k:[]) = [index n (last k)]
      indices _ [] = []
      -- Register various special variables
      index i k = withData "index" (DataValue (NumberV (realToFrac (i :: Integer)))) k
      stepKV (k,v) = withData "key" (DataValue (StringV k))
        . withName par1 (StringV k) . withName par2 v . redefineVariable "this" v $ eval thenp
      step v = redefineVariable "this" v . withName par1 v $ eval thenp
      frst = withData "first" (DataValue (BoolV True))
      last = withData "last" (DataValue (BoolV True))
      -- Register blockparams if they were supplied
      withName Nothing _ k = k
      withName (Just (Param n)) v k = withVariable n v k
      listIdx i k = withName par2 (NumberV (realToFrac i)) k
  liftBMX go

truthy :: Value -> Bool
truthy v = case v of
  BoolV b -> b
  NullV -> False
  UndefinedV -> False
  StringV t -> not (T.null t)
  NumberV i -> i /= 0
  ContextV c -> c /= mempty
  ListV l -> not (null l)

falsey :: Value -> Bool
falsey = not . truthy
