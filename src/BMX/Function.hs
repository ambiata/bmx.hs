{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wwarn #-} -- FIX remove
module BMX.Function (
    Helper
  , Decorator
  , Partial
  -- *
  , value
  , string
  , number
  , boolean
  , context
  , nullv
  , undef
  -- *
  , runHelper
  , runBlockHelper
  , runPartial
  , withDecorator
  , withBlockDecorator
  ) where

import           BMX.Data

import           P

type Helper m = HelperT (BMX m)
type Decorator m = DecoratorT (BMX m)
type Partial m = PartialT (BMX m)

-- -----------------------------------------------------------------------------
-- Argument parsers for helpers / decorators

value :: Monad m => FunctionT m Value
value = one "value" (const True)

string :: Monad m => FunctionT m Value
string = one "string" isString
  where isString (StringV _) = True
        isString _ = False

number :: Monad m => FunctionT m Value
number = one "number" isNum
  where isNum (IntV _) = True
        isNum _ = False

boolean :: Monad m => FunctionT m Value
boolean = one "boolean" isBool
  where isBool (BoolV _) = True
        isBool _ = False

nullv :: Monad m => FunctionT m Value
nullv = one "null" isNull
  where isNull NullV = True
        isNull _ = False

undef :: Monad m => FunctionT m Value
undef = one "undefined" isUndef
  where isUndef UndefinedV = True
        isUndef _ = False

context :: Monad m => FunctionT m Context
context = do
  (ContextV c) <- one "context" isContext
  return c
  where isContext (ContextV _) = True
        isContext _ = False

-- -----------------------------------------------------------------------------
-- Running / using a helper, partial or decorator

runHelper :: Monad m => [Value] -> Helper m -> BMX m Value
runHelper _ (BlockHelper _) = err (TypeError "helper" "block helper")
runHelper v (Helper h) = runFunctionT v h >>= either helpE return

runBlockHelper :: Monad m => [Value] -> Helper m -> Program -> Program -> BMX m Page
runBlockHelper _ (Helper _) _ _ = err (TypeError "block helper" "helper")
runBlockHelper v (BlockHelper h) ifp elsep = do
  fun <- runFunctionT v (h ifp elsep)
  either helpE return fun

-- FIX handle partial blocks
-- Partial blocks have two use cases:
--     1. Rendered up front and added to the context as @partial-block
--     2. Failover for when the named partial isn't found
--
--     #2 can be handled above this level in evalPartialBlock
--     #1 can be handled above this level with a local context change
runPartial :: (Applicative m, Monad m) => [Value] -> Partial m -> BMX m Page
runPartial v (Partial p) = partial
  where
    partial = runFunctionT v partialArg >>= either partE return
    partialArg = try customCtx <|> noCtx
    --
    customCtx = do
      c <- context
      liftBMX (withContext c p)
    --
    noCtx = liftBMX p

-- | Run a Decorator, then a continuation in the same environment
withDecorator :: Monad m => [Value] -> Decorator m -> BMX m Page -> BMX m Page
withDecorator _ (BlockDecorator _) _ = err (TypeError "decorator" "block decorator")
withDecorator v (Decorator d) k = runFunctionT v (d k) >>= either decoE return

-- | Run a block decorator, then a continuation
withBlockDecorator :: Monad m => [Value] -> Program -> Decorator m -> BMX m Page -> BMX m Page
withBlockDecorator _ _ (Decorator _) _ = err (TypeError "block decorator" "decorator")
withBlockDecorator v b (BlockDecorator d) k = runFunctionT v (d b k) >>= either decoE return

-- Take a list of Decorators and their values, along with a Program,
-- and thread the continuation along
-- foldDecorators :: Monad m => ??

-- -----------------------------------------------------------------------------
-- Util

helpE :: Monad m => FunctionError -> BMX m a
helpE = err . HelperError

partE :: Monad m => FunctionError -> BMX m a
partE = err . PartialError

decoE :: Monad m => FunctionError -> BMX m a
decoE = err . DecoratorError