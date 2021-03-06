{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DeriveGeneric #-}

module Logic.Modal where

import Control.Monad
import Data.IORef
import Data.Map (Map)
import qualified Data.Map as Map
import Control.Distributed.Process
import Data.Functor.Compose
import Data.Binary
import Control.Comonad
import Data.Functor.Adjunction
import Data.Distributive
import Data.Functor.Rep
import Control.Distributed.Process.Serializable

-- | The composition of two type constructors.
type (f :.: g) = Compose f g

-- | A type synonym for convenience
type f -| g = Adjunction f g

-- | The composition of two adjoint applicative functors gives a monad
instance (f -| g, Applicative f, Applicative g) => Monad (g :.: f) where
    return = Compose . unit
    m >>= f = Compose . fmap (rightAdjunct (getCompose . f)) . getCompose $ m

-- | The composition of two adjoint applicative functors gives a comonad, in the
-- opposite direction.
instance (f -| g) => Comonad (f :.: g) where
    extract = counit . getCompose
    extend f = Compose . fmap (leftAdjunct (f . Compose)) . getCompose

-- This type class is exactly equivalent to ComonadApply, as witnessed by the
-- below (commented out) instance.
class CModalS4 box where
    axiom4 :: box p -> box (box p)
    axiomT :: box p -> p
    axiomK :: box (p -> q) -> box p -> box q

instance ComonadApply w => CModalS4 (S4Witness w) where
    axiom4 = Valhalla . fmap Valhalla . duplicate . witnessMe
    axiomT = extract . witnessMe
    axiomK (Valhalla f) (Valhalla a) = Valhalla (f <@> a)

newtype S4Witness w a = Valhalla { witnessMe :: w a }

type ModalS4 = ComonadApply

-- Now, we're ready to build up modal s5. We'll specify that the box and diamond
-- uniquely determine each other, and that the axiom they must satisfy is the
-- axiom B. axiom 5 (dia a -> box (dia a))
class (Monad dia, ModalS4 box) => ModalS5 box dia where
    axiomB :: a -> box (dia a)

instance (g -| u, u -| f, ModalS4 (u :.: f), Applicative u, Applicative g) => ModalS5 (u :.: f) (u :.: g) where
    axiomB = unit

data U a
    deriving (Functor)

instance Applicative U where
    pure = undefined
    (<*>) = undefined

instance ComonadApply (U :.: F) where
    (<@>) = undefined

instance Adjunction U F where
    unit = undefined
    counit = undefined

instance Adjunction G U where
    unit = undefined
    counit = undefined

instance Representable U where
    type Rep U = U Int
    tabulate = undefined
    index = undefined

instance Distributive U where

data F a
    deriving (Functor)

instance Representable F where
    type Rep F = F Int
    tabulate = undefined
    index = undefined

instance Distributive F where

data G a
    deriving (Functor)

instance Applicative G where
    pure = undefined
    (<*>) = undefined

type Box = U :.: F
type Dia = U :.: G

pls :: ModalS5 Box Dia => ()
pls = ()

fetch
    :: forall k a. (Serializable k, Serializable a)
    => k
    -> ProcessId
    -> Process (Response k a)
fetch k pid = do
    self <- getSelfPid
    send pid (self, Fetch k :: Fetch k a)
    expect

fetchListen
    :: forall k a. (Serializable k, Serializable a, Ord k)
    => IORef (Map k a)
    -> Process ()
fetchListen ref = forever $ do
    (pid, Fetch k) <- expect :: Process (ProcessId, Fetch k a)
    table <- liftIO $ readIORef ref
    send pid (Response (Map.lookup k table) :: Response k a)


newtype Fetch k a = Fetch k
    deriving (Binary)

newtype Response k a = Response (Maybe a)
    deriving (Binary)
