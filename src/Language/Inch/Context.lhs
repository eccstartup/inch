> {-# LANGUAGE DeriveFunctor, DeriveFoldable, TypeOperators, FlexibleContexts,
>              GADTs, RankNTypes, TypeSynonymInstances,
>              MultiParamTypeClasses, FlexibleInstances #-}

> module Language.Inch.Context where

> import Control.Applicative
> import Control.Monad.Error
> import Control.Monad.State
> import Control.Monad.Writer hiding (All)
> import qualified Data.Map as Map
> import Text.PrettyPrint.HughesPJ

> import Language.Inch.BwdFwd
> import Language.Inch.Kind
> import Language.Inch.Type
> import Language.Inch.Syntax hiding (Alternative)
> import Language.Inch.PrettyPrinter
> import Language.Inch.Kit
> import Language.Inch.Error

> type Bindings = Map.Map TmName (Maybe Sigma, Bool)

> data TmLayer  =  PatternTop  (TmName ::: Sigma)
>               |  CaseTop
>               |  FunTop
>               |  GenMark
>               |  GuardTop
>               |  LamBody (TmName ::: Tau)
>               |  LetBindings {letBindings :: Bindings}
>               |  LetBody {letBindings :: Bindings}

> instance Show TmLayer where
>   show (PatternTop (x ::: _))  = "PatternTop " ++ x
>   show CaseTop                 = "CaseTop"
>   show FunTop                  = "FunTop"
>   show GenMark                 = "GenMark"
>   show GuardTop                = "GuardTop"
>   show (LamBody (x ::: _))     = "LamBody " ++ x
>   show (LetBindings _)         = "LetBindings"
>   show (LetBody _)             = "LetBody"

> instance Pretty TmLayer where
>   pretty l = const $ text $ show l

> matchLayer :: TmLayer -> TmLayer -> Bool
> matchLayer (PatternTop (x ::: _))  (PatternTop (y ::: _))  = x == y
> matchLayer CaseTop                 CaseTop                 = True
> matchLayer FunTop                  FunTop                  = True
> matchLayer GenMark                 GenMark                 = True
> matchLayer GuardTop                GuardTop                = True
> matchLayer (LamBody (x ::: _))     (LamBody (y ::: _))     = x == y
> matchLayer (LetBindings _)         (LetBindings _)         = True
> matchLayer (LetBody _)             (LetBody _)             = True
> matchLayer _                       _                       = False


The |withLayerExtract| function takes two boolean parameters: |stop|
indicates whether the layer should stop numeric unification
constraints, and |forget| indicates whether hypotheses should be dropped
when the layer is extracted.

> withLayerExtract :: Bool -> Bool -> TmLayer -> (TmLayer -> a) -> Contextual t -> Contextual (t, a)
> withLayerExtract stop forget l f m = do
>     modifyContext (:< Layer l stop)
>     t <- m
>     (g, a) <- extract <$> getContext
>     putContext g
>     return (t, a)
>   where
>     extract (g :< Layer l' z) | matchLayer l l'  = (g, f l')
>                               | otherwise        = error $ "withLayerExtract: wrong layer in " ++ renderMe (g :< Layer l' z) ++ " (looking for " ++ renderMe l ++ ")"
>     extract (g :< Constraint Given _) | forget = extract g
>     extract (g :< e)                         = (g' :< e, a)
>       where (g', a) = extract g
>     extract B0 = error $ "withLayerExtract: ran out of context"

> withLayer :: Bool -> Bool -> TmLayer -> Contextual t -> Contextual t
> withLayer stop forget l m = fst <$> withLayerExtract stop forget l (const ()) m



> data CStatus = Given | Wanted
>   deriving Show


> data TyDef k = Hole | Some (Type k) | Fixed | Exists
>   deriving Show

> instance FV (TyDef k) () where
>     fvFoldMap f (Some t)  = fvFoldMap f t
>     fvFoldMap _ _         = mempty

> instance Pretty (TyDef k) where
>   pretty Hole      _ = text "?"
>   pretty Fixed     _ = text "!"
>   pretty Exists    _ = text "Ex"
>   pretty (Some t)  l = pretty (fogSysTy t) l


> type TyEntry k = Var () k := TyDef k

> instance FV (TyEntry k) () where
>     fvFoldMap f (b := d) = fvFoldMap f b <.> fvFoldMap f d

> instance Pretty (TyEntry k) where
>     pretty (a := d) _ = prettySysVar a <+> text ":="
>       <+> prettyHigh d <+> text ":" <+> prettyHigh (fogKind (varKind a))


> data AnyTyEntry where
>     TE :: TyEntry k -> AnyTyEntry

> instance Show AnyTyEntry where
>     show (TE t) = show t

> instance FV AnyTyEntry () where
>     fvFoldMap f (TE t) = fvFoldMap f t




> data Entry where
>     A           :: TyEntry k -> Entry
>     Layer       :: TmLayer -> Bool -> Entry
>     Constraint  :: CStatus -> Predicate -> Entry

> instance Pretty Entry where
>   pretty (A a)                  _ = prettyHigh a
>   pretty (Layer l _)            _ = prettyHigh l
>   pretty (Constraint Given p)   _ =
>       braces (prettyHigh $ fogSysPred p) <> text "!!"
>   pretty (Constraint Wanted p)  _ =
>       braces (prettyHigh $ fogSysPred p) <> text "??"



> defToMaybe :: TyDef k -> Maybe (Type k)
> defToMaybe (Some t)  = Just t
> defToMaybe _         = Nothing

> type Context  = Bwd Entry
> type Suffix   = Fwd AnyTyEntry

> (<><) :: Context -> Suffix -> Context
> _Gamma <>< F0                   = _Gamma
> _Gamma <>< (TE e :> _Xi)  = _Gamma :< A e <>< _Xi
> infixl 8 <><

> data ZipState = St  {  nextFreshInt :: Int
>                     ,  context   :: Context
>                     ,  tyCons    :: Map.Map TyConName (Ex Kind)
>                     ,  tmCons    :: Map.Map TmConName Sigma
>                     ,  bindings  :: Bindings
>                     }


Initial state

> tyInteger, tyBool, tyOrdering, tyUnit, tyChar, tyString :: Ty a KSet
> tyInteger     = TyCon "Integer" KSet
> tyBool        = TyCon "Bool" KSet
> tyOrdering    = TyCon "Ordering" KSet
> tyUnit        = TyCon unitTypeName KSet
> tyChar        = TyCon "Char" KSet
> tyString      = tyList tyChar

> tyMaybe, tyList :: Ty a KSet -> Ty a KSet
> tyMaybe       = TyApp (TyCon "Maybe" (KSet :-> KSet))
> tyList        = TyApp (TyCon listTypeName (KSet :-> KSet))

> tyEither, tyTuple :: Ty a KSet -> Ty a KSet -> Ty a KSet
> tyEither a b  = TyApp (TyApp (TyCon "Either" (KSet :-> KSet :-> KSet)) a) b
> tyTuple       = TyApp . TyApp (TyCon tupleTypeName (KSet :-> KSet :-> KSet))


> initialState :: ZipState
> initialState = St 0 B0 initTyCons initTmCons initBindings
>   where
>     initTyCons = Map.fromList $
>       ("Char",        Ex KSet) :
>       ("Integer",     Ex KSet) :
>       (listTypeName,  Ex (KSet :-> KSet)) :
>       (unitTypeName,  Ex KSet) :
>       (tupleTypeName, Ex (KSet :-> KSet :-> KSet)) :
>       []
>     initTmCons = Map.fromList $
>       (listNilName,   Bind All "a" KSet (tyList (TyVar (BVar Top)))) :
>       (listConsName,  Bind All "a" KSet (TyVar (BVar Top) --> tyList (TyVar (BVar Top)) --> tyList (TyVar (BVar Top)))) :
>       (unitConsName,  tyUnit) :
>       (tupleConsName, Bind All "a" KSet (Bind All "b" KSet (TyVar (BVar (Pop Top)) --> TyVar (BVar Top) --> tyTuple (TyVar (BVar (Pop Top))) (TyVar (BVar Top))))) :
>       []
>     initBindings = Map.fromList $
>       []




> type Contextual a          = StateT ZipState (Either ErrorData) a
> type ContextualWriter w a  = WriterT w (StateT ZipState (Either ErrorData)) a


Fresh names

> freshVar :: MonadState ZipState m =>
>                 VarState -> String -> Kind k -> m (Var () k)
> freshVar vs s k = do
>     st <- get
>     let beta = nextFreshInt st
>     put st{nextFreshInt = succ beta}
>     return $ FVar (N s beta vs) k

> fresh :: MonadState ZipState m =>
>              VarState -> String -> Kind k -> TyDef k -> m (Var () k)
> fresh vs s k d = do
>     v <- freshVar vs s k
>     modifyContext (:< A (v := d))
>     return v

> unknownTyVar :: (Functor m, MonadState ZipState m) =>
>                     String -> Kind k -> m (Type k)
> unknownTyVar s k = TyVar <$> fresh SysVar s k Hole

> tyVarNamesInScope :: (Functor m, MonadState ZipState m) => m [String]
> tyVarNamesInScope = help <$> getContext
>   where
>     help :: Context -> [String]
>     help B0                 = []
>     help (g :< A (v := _))  = nameToString (varName v) : help g
>     help (g :< _)           = help g


Context

> getContext :: MonadState ZipState m => m Context
> getContext = gets context
>
> putContext :: MonadState ZipState m => Context -> m ()
> putContext _Gamma = modify $ \ st -> st{context = _Gamma}
>
> modifyContext :: MonadState ZipState m => (Context -> Context) -> m ()
> modifyContext f = getContext >>= putContext . f


Type constructors

> insertTyCon :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    TyConName -> Ex Kind -> m ()
> insertTyCon x k = do
>     st <- get
>     when (Map.member x (tyCons st)) $ errDuplicateTyCon x
>     put st{tyCons = Map.insert x k (tyCons st)}

> lookupTyCon :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    TyConName -> m (Ex Kind)
> lookupTyCon x = do
>     tcs <- gets tyCons
>     case Map.lookup x tcs of
>         Just k   -> return k
>         Nothing  -> missingTyCon x


Data constructors

> insertTmCon :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    TmConName -> Sigma -> m ()
> insertTmCon x ty = do
>     st <- get
>     when (Map.member x (tmCons st)) $ errDuplicateTmCon x
>     put st{tmCons = Map.insert x ty (tmCons st)}

> lookupTmCon :: (MonadState ZipState m, MonadError ErrorData m) =>
>                     TmConName -> m Sigma
> lookupTmCon x = do
>     tcs <- gets tmCons
>     case Map.lookup x tcs of
>         Just ty  -> return ty
>         Nothing  -> missingTmCon x



Bindings

> lookupBindingIn :: (MonadError ErrorData m) =>
>                    TmName -> Bindings -> m (Term () ::: Sigma, Bool)
> lookupBindingIn x bs = case Map.lookup x bs of
>     Just (Just ty, u)  -> return (TmVar x ::: ty, u)
>     Just (Nothing, _)  -> erk "Mutual recursion requires explicit signatures"
>     Nothing            -> missingTmVar x

> insertBindingIn :: MonadError ErrorData m =>
>                    String -> a -> Map.Map String a -> m (Map.Map String a)
> insertBindingIn x ty bs = do
>     when (Map.member x bs) $ errDuplicateTmVar x
>     return $ Map.insert x ty bs

> lookupTopBinding :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    TmName -> m (Term () ::: Sigma, Bool)
> lookupTopBinding x = lookupBindingIn x =<< gets bindings 

> modifyTopBindings :: MonadState ZipState m => (Bindings -> m Bindings) -> m ()
> modifyTopBindings f = do
>     st <- get
>     bs <- f (bindings st)
>     put st{bindings = bs}

> insertTopBinding :: (MonadState ZipState m, MonadError ErrorData m) =>
>                      TmName -> (Maybe Sigma, Bool) -> m ()
> insertTopBinding x ty = modifyTopBindings $ insertBindingIn x ty

> updateTopBinding :: (MonadState ZipState m, MonadError ErrorData m) =>
>                      TmName -> (Maybe Sigma, Bool) -> m ()
> updateTopBinding x ty = modifyTopBindings (return . Map.insert x ty)


> lookupBinding :: (MonadError ErrorData m, MonadState ZipState m, Alternative m) =>
>                      TmName -> m (Term () ::: Sigma, Bool)
> lookupBinding x = help =<< getContext
>   where
>     help B0                               = lookupTopBinding x
>     help (_ :< Layer (LetBindings bs) _)  = lookupBindingIn x bs
>     help (g :< _)                         = help g

> modifyBindings :: (Bindings -> Contextual Bindings) -> Contextual ()
> modifyBindings f = flip help [] =<< getContext
>   where
>     help :: Context -> [Entry] -> Contextual ()
>     help B0 _ = modifyTopBindings f
>     help (g :< Layer (LetBindings bs) z) h = do
>         bs' <- f bs
>         putContext $ (g :< Layer (LetBindings bs') z) <><< h
>     help (g :< e) h = help g (e:h)

> insertBinding, updateBinding :: TmName -> (Maybe Sigma, Bool) -> Contextual ()
> insertBinding x ty = modifyBindings $ insertBindingIn x ty
> updateBinding x ty = modifyBindings $ return . Map.insert x ty



> {-
> seekTy :: Context -> TyName -> Ex Type
> seekTy (g :< A (b := d ::: k))  a | a == b  = case d of  Some t  -> t
>                                                          _       -> TyVar (FVar b k)
> seekTy (g :< _)                 a           = seekTy g a
> seekTy B0                       a           = error "seekTy: missing!"
> -}

> {-

> expandContext :: Context -> Context
> expandContext B0 = B0
> expandContext (g :< A (a := Some t))  = expandContext g
> expandContext (g :< a@(A _))          = expandContext g :< a
> expandContext (g :< Constraint s p)   =
>     expandContext g :< Constraint s (fmap (substTy (expandTyVar g)) p)
> expandContext (g :< Layer l) =
>     expandContext g :< Layer (bindLayerTypes (expandTyVar g) l)


> expandTyVar :: Context -> Var () k -> Type k
> expandTyVar g a = case seek g a of
>     Some d  -> expandType g d
>     _       -> TyVar a
>   where
>     seek (g :< A (b := d))  a = hetEq a b d (seek g a)
>     seek (g :< _)           a           = seek g a
>     seek B0                 a           = error "expandTyVar: erk"

> expandType :: Context -> Type k -> Type k
> expandType g = substTy (expandTyVar g)
    
> expandPred :: Context -> Predicate -> Predicate
> expandPred g = fmap (expandType g)

> niceType :: Type KSet -> Contextual (Type KSet)
> niceType t = (\ g -> simplifyTy (expandType g t)) <$> getContext

> nicePred :: Predicate -> Contextual Predicate
> nicePred p = (\ g -> simplifyPred (expandPred g p)) <$> getContext

> -}



> lookupTyVar :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    Binder -> Bwd (Ex (Var ())) -> String -> m (Ex (Var ()))
> lookupTyVar b (g :< Ex a) x
>     | varNameEq a x  = checkBinder b a >> return (Ex a)
>     | otherwise      = lookupTyVar b g x
> lookupTyVar b B0 x = getContext >>= seek
>   where
>     seek B0 = missingTyVar x
>     seek (_ :< A (a := _)) | varNameEq a x = checkBinder b a >> return (Ex a)
>     seek (g :< _) = seek g

> checkBinder :: (MonadState ZipState m, MonadError ErrorData m) =>
>                    Binder -> Var () k -> m ()
> checkBinder All  _  = return ()
> checkBinder Pi   a  = case (varKind a, varBinder a) of
>                         (KNum, Just Pi)  -> return ()
>                         (KNum, _)        -> errBadBindingLevel a
>                         _                -> errNonNumericVar a


> lookupTmVar :: (Alternative m, MonadState ZipState m, MonadError ErrorData m) =>
>                    TmName -> m (Term () ::: Sigma)
> lookupTmVar x = getContext >>= seek
>   where
>     seek B0 = fst <$> lookupTopBinding x
>     seek (_ :< Layer (LamBody (y ::: ty)) _)
>         | x == y = return $ TmVar y ::: ty
>     seek (g :< Layer (LetBody bs) _)   = (fst <$> lookupBindingIn x bs) <|> seek g
>     seek (g :< Layer (LetBindings bs) _)  = (fst <$> lookupBindingIn x bs) <|> seek g
>     seek (g :< Layer (PatternTop (y ::: ty)) _)
>         | x == y     = return $ TmVar y ::: ty
>         | otherwise  = seek g
>     seek (g :< _) = seek g