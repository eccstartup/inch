> {-# LANGUAGE TypeSynonymInstances, FlexibleInstances, FlexibleContexts,
>              TypeOperators, GADTs #-}

> module PrettyPrinter where

> import Data.Foldable
> import Data.List
> import Text.PrettyPrint.HughesPJ

> import TyNum
> import Kind
> import Type
> import BwdFwd
> import Syntax
> import Kit


> data Size = ArgSize | AppSize | ArrSize | LamSize
>     deriving (Bounded, Eq, Ord, Show)

> class Pretty x where
>     pretty :: x -> Size -> Doc

> prettyLow :: Pretty x => x -> Doc
> prettyLow = flip pretty minBound

> prettyHigh :: Pretty x => x -> Doc
> prettyHigh = flip pretty maxBound

> wrapDoc :: Size -> Doc -> Size -> Doc
> wrapDoc dSize d curSize
>   | dSize > curSize  = parens d
>   | otherwise        = d

> prettyProgram :: Program -> Doc
> prettyProgram = vcat . intersperse (text " ") . map (prettyHigh . fog)


> renderMe :: Pretty a => a -> String
> renderMe x = renderStyle style{ribbonsPerLine=1.2, lineLength=80} (prettyHigh x)

> d1 <++> d2 = sep [d1, nest 2 d2]
> infix 2 <++>


> class Ord a => PrettyVar a where
>     prettyVar :: a -> Doc


> instance PrettyVar String where
>     prettyVar = text

> instance PrettyVar (String, Int) where
>     prettyVar (s, -1) = text s
>     prettyVar (s, n) = text s <> char '_' <> int n

> instance PrettyVar (Var () k) where
>     prettyVar (FVar x k) = prettyVar x


> instance Pretty SKind where
>     pretty SKSet       = const $ text "*"
>     pretty SKNum       = const $ text "Num"
>     pretty (k :--> l)  = wrapDoc AppSize $
>         pretty k ArgSize <+> text "->" <+> pretty l AppSize

> instance Pretty Binder where
>     pretty Pi _   = text "pi"
>     pretty All _  = text "forall"

> instance Pretty STypeNum where
>     pretty (NumConst k)  = const $ integer k
>     pretty (NumVar a)    = const $ prettyVar a
>     pretty (m :+: NumConst k) | k < 0 = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "-" <+> integer (-k)
>     pretty (m :+: Neg n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "-" <+> pretty n ArgSize
>     pretty (Neg m :+: n) = wrapDoc AppSize $ 
>         pretty n ArgSize <+> text "-" <+> pretty m ArgSize
>     pretty (m :+: n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "+" <+> pretty n ArgSize
>     pretty (m :*: n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "*" <+> pretty n ArgSize
>     pretty (Neg n) = wrapDoc AppSize $
>         text "-" <+> pretty n ArgSize

> instance Pretty SPredicate where
>     pretty (P c n m) = wrapDoc AppSize $
>         pretty n ArgSize <+> pretty c ArgSize <+> pretty m ArgSize

> instance Pretty Predicate where
>     pretty = pretty . fogPred

> instance Pretty Comparator where
>     pretty LS _ = text "<"
>     pretty LE _ = text "<=" 
>     pretty GR _ = text ">"
>     pretty GE _ = text ">="
>     pretty EL _ = text "~"

> instance Pretty SType where
>     pretty (STyVar v)                  = const $ prettyVar v
>     pretty (STyCon c)                  = const $ text c
>     pretty (STyApp (STyApp SArr s) t)  = wrapDoc ArrSize $ 
>         pretty s AppSize <+> text "->" <++> pretty t ArrSize
>     pretty (STyApp f s)  = wrapDoc AppSize $ 
>         pretty f AppSize <+> pretty s ArgSize
>     pretty (STyNum n) = pretty n
>     pretty (SBind b a k t) = prettyBind b (B0 :< (a, k)) $
>         alphaConvert [(a, a ++ "'")] t
>     pretty (SQual p t) = prettyQual (B0 :< p) t
>     pretty SArr = const $ text "(->)"

> prettyBind :: Binder -> Bwd (String, SKind) ->
>     SType -> Size -> Doc
> prettyBind b bs (SBind b' a k t) | b == b' = prettyBind b (bs :< (a, k)) $
>     alphaConvert [(a, a ++ "'")] t
> prettyBind b bs t = wrapDoc LamSize $ prettyHigh b
>         <+> prettyBits (trail bs)
>         <+> text "." <++> pretty t ArrSize
>   where
>     prettyBits []             = empty
>     prettyBits ((a, SKSet) : aks) = text a <+> prettyBits aks
>     prettyBits ((a, k) : aks) = parens (text a <+> text "::" <+> prettyHigh k) <+> prettyBits aks


> prettyQual :: Bwd SPredicate -> SType -> Size -> Doc
> prettyQual ps (SQual p t) = prettyQual (ps :< p) t
> prettyQual ps t = wrapDoc ArrSize $
>     prettyPreds (trail ps) <+> text "=>" <++> pretty t ArrSize
>   where
>     prettyPreds ps = hsep (punctuate (text ",") (map prettyHigh ps))

> instance Pretty (Type k) where
>     pretty = pretty . fogTy


> instance Pretty STerm where
>     pretty (TmVar x)    = const $ prettyVar x
>     pretty (TmCon s)    = const $ text s
>     pretty (TmInt k)    = const $ integer k
>     pretty (TmApp f s)  = wrapDoc AppSize $
>         pretty f AppSize <++> pretty s ArgSize
>     pretty (TmBrace n)  = const $ braces $ prettyHigh n 
>     pretty (Lam x t)   = prettyLam (text x) t
>     pretty (Let ds t)  = wrapDoc ArgSize $ text "let" <+> vcatSpacePretty ds $$ text "in" <+> prettyHigh t
>     pretty (t :? ty)   = wrapDoc ArrSize $ 
>         pretty t AppSize <+> text "::" <+> pretty ty maxBound

> prettyLam :: Doc -> STerm -> Size -> Doc
> prettyLam d (Lam x t) = prettyLam (d <+> prettyVar x) t
> prettyLam d t = wrapDoc LamSize $
>         text "\\" <+> d <+> text "->" <+> pretty t AppSize

> instance Pretty Term where
>     pretty = pretty . fog

> instance Pretty SDeclaration where
>     pretty (DD d) = pretty d 
>     pretty (FD f) = pretty f

> instance Pretty SDataDeclaration where
>     pretty (DataDecl n k cs) _ = hang (text "data" <+> text n
>         <+> (if k /= SKSet then text "::" <+> prettyHigh k else empty)
>         <+> text "where") 2 $
>             vcat (map prettyHigh cs)

> instance Pretty SFunDeclaration where
>     pretty (FunDecl n Nothing ps) _ = vcat (map ((prettyVar n <+>) . prettyHigh) ps)
>     pretty (FunDecl n (Just ty) ps) _ = vcat $ (prettyVar n <+> text "::" <+> prettyHigh ty) : map ((prettyVar n <+>) . prettyHigh) ps


> instance (PrettyVar x, Pretty p) => Pretty (x ::: p) where
>   pretty (x ::: p) _ = prettyVar x <+> text "::" <+> prettyHigh p


> instance Pretty SPattern where
>     pretty (Pat vs Nothing e) _ =
>         hsep (map prettyLow vs) <+> text "=" <++> prettyHigh e
>     pretty (Pat vs (Just g) e) _ =
>         hsep (map prettyLow vs) <+> text "|" <+> prettyHigh g
>                                     <+> text "=" <++> prettyHigh e

> instance Pretty SGuard where
>     pretty (ExpGuard t)  = pretty t
>     pretty (NumGuard p)  = const $ braces (fsepPretty p)


> instance Pretty SPatternTerm where
>     pretty (PatVar x)    = const $ prettyVar x
>     pretty (PatCon c []) = const $ text c
>     pretty (PatCon "+" [a, b]) = wrapDoc AppSize $
>         prettyLow a <+> text "+" <+> prettyLow b
>     pretty (PatCon c ps) = wrapDoc AppSize $
>                                text c <+> hsep (map prettyLow ps)
>     pretty PatIgnore = const $ text "_"
>     pretty (PatBrace Nothing k)   = const $ braces $ integer k
>     pretty (PatBrace (Just a) 0)  = const $ braces $ prettyVar a
>     pretty (PatBrace (Just a) k)  = const $ braces $
>                                     prettyVar a <+> text "+" <+> integer k

> instance Pretty SNormalPred where
>     pretty p = pretty (reifyPred p)

> instance Pretty NormalPredicate where
>     pretty p = pretty (reifyPred p)

> instance Pretty SNormalNum where
>     pretty n _ = prettyHigh $ simplifyNum $ reifyNum n

> instance Pretty x => Pretty (Bwd x) where
>     pretty bs _ = fsep $ punctuate (text ",") (map prettyHigh (trail bs))

> instance Pretty x => Pretty (Fwd x) where
>     pretty bs _ = fsep $ punctuate (text ",") $ map prettyHigh $ Data.Foldable.foldr (:) [] bs


> fsepPretty xs  = fsep . punctuate (text ",") . map prettyHigh $ xs
> vcatSpacePretty xs  = vcat . intersperse (text " ") . map prettyHigh $ xs
> vcatPretty xs  = vcat . map prettyHigh $ xs