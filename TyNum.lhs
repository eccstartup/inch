> {-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable, GADTs #-}

> module TyNum where

> import Control.Applicative
> import Data.Foldable
> import Data.Traversable

> import Kit
> import Num

> type TypeNum          = TyNum TyName
> type Predicate        = Pred TyName


> data TyNum a where
>     NumConst  :: Integer -> TyNum a
>     NumVar    :: a -> TyNum a
>     (:+:)     :: TyNum a -> TyNum a -> TyNum a
>     (:*:)     :: TyNum a -> TyNum a -> TyNum a
>     Neg       :: TyNum a -> TyNum a
>   deriving (Eq, Show, Functor, Foldable, Traversable)

> instance Monad TyNum where
>     return = NumVar
>     NumConst k  >>= f = NumConst k
>     NumVar a    >>= f = f a
>     m :+: n     >>= f = (m >>= f) :+: (n >>= f)
>     m :*: n     >>= f = (m >>= f) :*: (n >>= f)
>     Neg n       >>= f = Neg (n >>= f)

> simplifyNum :: TyNum a -> TyNum a
> simplifyNum (n :+: m) = case (simplifyNum n, simplifyNum m) of
>     (NumConst k,  NumConst l)  -> NumConst (k+l)
>     (NumConst 0,  m')          -> m'
>     (n',          NumConst 0)  -> n'
>     (n',          m')          -> n' :+: m'
> simplifyNum (n :*: m) = case (simplifyNum n, simplifyNum m) of
>     (NumConst k,     NumConst l)     -> NumConst (k*l)
>     (NumConst 0,     m')             -> NumConst 0
>     (NumConst 1,     m')             -> m'
>     (NumConst (-1),  m')             -> Neg m'
>     (n',             NumConst 0)     -> NumConst 0
>     (n',             NumConst 1)     -> n'
>     (n',             NumConst (-1))  -> Neg n'
>     (n',             m')             -> n' :*: m'
> simplifyNum (Neg n) = case simplifyNum n of
>     NumConst k  -> NumConst (-k)
>     n'          -> Neg n'
> simplifyNum t = t

> instance (Eq a, Show a) => Num (TyNum a) where
>     (+)          = (:+:)
>     (*)          = (:*:)
>     negate       = Neg
>     fromInteger  = NumConst
>     abs          = error "no abs"
>     signum       = error "no signum"


> data Pred a where
>     (:<=:) :: TyNum a -> TyNum a -> Pred a
>   deriving (Eq, Show, Functor, Foldable, Traversable)

> bindPred :: (a -> TyNum b) -> Pred a -> Pred b
> bindPred g (n :<=: m)  = (n >>= g) :<=: (m >>= g)

> simplifyPred :: Pred a -> Pred a
> simplifyPred (m :<=: n) = simplifyNum m :<=: simplifyNum n

> normalisePred :: (Applicative m, Monad m) => Predicate -> m NormalNum
> normalisePred (m :<=: n) = normaliseNum (n :+: Neg m)


> type NormNum a = GExp () a
> type NormalNum = NormNum TyName

> normaliseNum :: (Applicative m, Monad m) => TypeNum -> m NormalNum
> normaliseNum (NumConst k)  = return $ normalConst k
> normaliseNum (NumVar a)    = return $ embedVar a
> normaliseNum (m :+: n)     = (+~) <$> normaliseNum m <*> normaliseNum n
> normaliseNum (m :*: n)     = do
>     m'  <- normaliseNum m
>     n'  <- normaliseNum n
>     case (getConstant m', getConstant n') of
>         (Just i,   Just j)   -> return $ normalConst (i * j)
>         (Just i,   Nothing)  -> return $ i *~ n'
>         (Nothing,  Just j)   -> return $ j *~ m'
>         (Nothing,  Nothing)  -> fail "Non-linear numeric expression"
> normaliseNum (Neg n)       = negateGExp <$> normaliseNum n

> normalConst k = mkGExp [] [((), k)]


> reifyNum :: NormalNum -> TypeNum
> reifyNum = simplifyNum . foldGExp (\ k n m -> NumConst k * NumVar n + m) NumConst