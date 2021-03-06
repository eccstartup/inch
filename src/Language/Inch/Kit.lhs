> {-# LANGUAGE TypeOperators, GADTs, DeriveFunctor, DeriveFoldable, DeriveTraversable,
>              RankNTypes, TypeFamilies #-}

> module Language.Inch.Kit where

> import Control.Applicative
> import Data.Foldable hiding (foldr)
> import Data.List
> import Data.Monoid
> import Data.Traversable
> import Debug.Trace


> (<.>) :: Monoid a => a -> a -> a
> (<.>) = mappend


> data Ex f where
>     Ex :: f a -> Ex f

> unEx :: Ex t -> (forall a . t a -> b) -> b
> unEx (Ex t) f = f t

> unEx2 :: (forall a . t a -> b) -> Ex t -> b
> unEx2 f (Ex t) = f t

> mapEx :: (forall a . f a -> g a) -> Ex f -> Ex g
> mapEx f (Ex t) = Ex (f t)

> travEx :: Functor t => (forall a . f a -> t (g a)) -> Ex f -> t (Ex g)
> travEx f (Ex t) = Ex <$> f t


> class HetEq t where
>     hetEq :: t a -> t b -> (a ~ b => x) -> x -> x
>     (=?=) :: t a -> t b -> Bool
>     s =?= t = hetEq s t True False

> instance HetEq t => Eq (Ex t) where
>     Ex s == Ex t = s =?= t

> hetElem :: HetEq t => t a -> [Ex t] -> Bool
> hetElem _ []      = False
> hetElem x (Ex y:ys)  = x =?= y || hetElem x ys

> class HetOrd t where
>     (<?=) :: t a -> t b -> Bool     

> data S a where
>     S :: a -> S a
>     Z :: S a
>   deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

> bind :: (Functor f, Eq a) => a -> f a -> f (S a)
> bind x = fmap inS
>   where  inS y | x == y     = Z
>                | otherwise  = S y

> unbind :: Functor f => a -> f (S a) -> f a
> unbind x = fmap unS
>   where  unS Z      = x
>          unS (S a)  = a

> subst :: (Monad m, Eq a) => a -> m a -> m a -> m a
> subst a t = (>>= f)
>   where f b | a == b     = t
>             | otherwise  = return b

> wk :: Applicative f => (a -> f b) -> (S a -> f (S b))
> wk _ Z      = pure Z
> wk g (S a)  = fmap S (g a)


Really we want g to be a pointed functor!

> wkwk :: (Applicative f, Functor g) =>
>     (S b -> g (S b)) -> (a -> f (g b)) -> (S a -> f (g (S b)))
> wkwk p _ Z      = pure $ p Z
> wkwk _ g (S a)  = fmap S <$> g a


> data a :=   b  = a :=   b
>     deriving (Eq, Show, Functor, Foldable, Traversable)
> data a :::  b  = a :::  b
>     deriving (Eq, Show, Functor, Foldable, Traversable)
> infix 3 :=
> infix 4 :::

> tmOf :: a ::: b -> a
> tmOf (a ::: _) = a

> tyOf :: a ::: b -> b
> tyOf (_ ::: b) = b

> unzipAsc :: [(a ::: b)] -> ([a] ::: [b])
> unzipAsc xs = map tmOf xs ::: map tyOf xs



> mtrace :: Monad m => String -> m ()
> mtrace s = trace s (return ()) >>= \ () -> return ()



> newtype Id a = Id {unId :: a}
>     deriving (Functor, Foldable, Traversable)

> instance Applicative Id where
>     pure = Id
>     Id f <*> Id s = Id (f s)


> unions :: Eq a => [[a]] -> [a]
> unions = foldr union []