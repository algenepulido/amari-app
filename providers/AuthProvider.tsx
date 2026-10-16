import { createContext, useContext, useEffect, useRef, useState, PropsWithChildren } from 'react';
import { AppState } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import { supabase } from '@/lib/supabase';
import { Session, User } from '@supabase/supabase-js';
import { queryClient, queryKeys } from '@/lib/queryClient';
import type { MembershipTier } from '@/lib/theme';

interface AuthState {
  session: Session | null;
  user: User | null;
  tier: MembershipTier;
  isAdmin: boolean;
  isLoading: boolean;
  isPostAuthSetupComplete: boolean;
}

const AuthContext = createContext<AuthState>({
  session: null,
  user: null,
  tier: 'member',
  isAdmin: false,
  isLoading: true,
  isPostAuthSetupComplete: false,
});

export function useAuth() {
  return useContext(AuthContext);
}

export function AuthProvider({ children }: PropsWithChildren) {
  const [state, setState] = useState<AuthState>({
    session: null,
    user: null,
    tier: 'member',
    isAdmin: false,
    isLoading: true,
    isPostAuthSetupComplete: false,
  });

  function extractTierFromSession(session: Session | null): { tier: MembershipTier; isAdmin: boolean } {
    const appMeta = session?.user?.app_metadata;
    return {
      tier: (appMeta?.tier as MembershipTier) || 'member',
      isAdmin: appMeta?.is_admin === true,
    };
  }

  // Derive the effective tier and admin flag from live membership, so a downgrade or
  // suspension takes effect without waiting for the access token to refresh. The admin flag
  // fails closed: it is true only when the live check explicitly confirms it, so a failed or
  // errored check drops admin rather than keeping a stale elevated value from the token. The
  // tier keeps the token value as a first-paint hint when the live tier read cannot complete.
  const applyEffectiveTier = async (userId: string) => {
    try {
      const [tierRes, adminRes] = await Promise.all([
        supabase.rpc('get_member_tier'),
        supabase.rpc('is_admin'),
      ]);
      const isAdmin = !adminRes.error && adminRes.data === true;
      setState(prev => {
        if (prev.user?.id !== userId) return prev;
        const tier = !tierRes.error ? ((tierRes.data as MembershipTier) || 'member') : prev.tier;
        return { ...prev, tier, isAdmin };
      });
    } catch {
      // The live check could not complete. Fail admin closed; keep the token tier as a hint.
      setState(prev => (prev.user?.id === userId ? { ...prev, isAdmin: false } : prev));
    }
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      const { tier, isAdmin } = extractTierFromSession(session);
      setState({
        session,
        user: session?.user ?? null,
        tier,
        isAdmin,
        isLoading: false,
        isPostAuthSetupComplete: !session?.user,
      });
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      const { tier, isAdmin } = extractTierFromSession(session);
      setState(prev => {
        const sameUser = prev.user?.id === session?.user?.id;
        // On a token refresh for the same user, keep the live-derived tier and admin flag rather
        // than overwriting them with the token values, which can be stale: a suspended admin whose
        // token metadata was not rewritten would otherwise regain admin navigation. The live check
        // in the TOKEN_REFRESHED branch below reconciles them. On sign-in or a user change the
        // token is the first-paint hint.
        const keepLive = event === 'TOKEN_REFRESHED' && sameUser;
        return {
          ...prev,
          session,
          user: session?.user ?? null,
          tier: keepLive ? prev.tier : tier,
          isAdmin: keepLive ? prev.isAdmin : isAdmin,
          isLoading: false,
          isPostAuthSetupComplete: session?.user ? sameUser && prev.isPostAuthSetupComplete : true,
        };
      });

      if (event === 'SIGNED_IN') {
        queryClient.invalidateQueries();
      }

      if (event === 'TOKEN_REFRESHED') {
        if (session?.user) applyEffectiveTier(session.user.id);
        queryClient.invalidateQueries({ queryKey: queryKeys.corridor.all });
        queryClient.invalidateQueries({ queryKey: queryKeys.events.all });
        queryClient.invalidateQueries({ queryKey: queryKeys.aligned.all });
        queryClient.invalidateQueries({ queryKey: queryKeys.member.me });
      }

      if (event === 'SIGNED_OUT') {
        queryClient.clear();
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  // Keep the effective tier aligned with live membership: refresh it whenever the
  // signed-in user changes and each time the app returns to the foreground.
  useEffect(() => {
    const userId = state.user?.id;
    if (!userId) return;
    applyEffectiveTier(userId);
    const sub = AppState.addEventListener('change', (next) => {
      if (next === 'active') applyEffectiveTier(userId);
    });
    return () => sub.remove();
  }, [state.user?.id]);

  // Sync profile data from user_metadata / SecureStore to the members table.
  // Covers cases where the member row exists but has empty fields:
  //   - already_member (returning user with pending code)
  //   - Google sign-in (name from Google, city/industry empty)
  //   - Magic link opened on a different device (no SecureStore, but user_metadata has data)
  const syncProfileData = async (
    userId: string,
    pendingData?: {
      fullName?: string;
      city?: string;
      industry?: string;
      currentProject?: string;
      skills?: string[];
      interests?: string[];
    },
  ) => {
    try {
      // Fetch current member row
      const { data: member, error: fetchError } = await supabase
        .from('members')
        .select('full_name, city, industry, current_project, skills, interests')
        .eq('id', userId)
        .single();

      if (fetchError || !member) return;

      const userMeta = state.user?.user_metadata;
      const metaSkills = Array.isArray(userMeta?.skills) ? (userMeta.skills as string[]) : [];
      const metaInterests = Array.isArray(userMeta?.interests) ? (userMeta.interests as string[]) : [];

      // Build updates only for fields that are empty in the DB but available from sources
      const updates: Record<string, string | string[]> = {};

      if (!member.full_name || member.full_name === 'AMARI Member') {
        const name = pendingData?.fullName || userMeta?.full_name || userMeta?.name;
        if (name) updates.full_name = name;
      }

      if (!member.city) {
        const city = pendingData?.city || userMeta?.city;
        if (city) updates.city = city;
      }

      if (!member.industry) {
        const industry = pendingData?.industry || userMeta?.industry;
        if (industry) updates.industry = industry;
      }

      if (!member.current_project) {
        const currentProject = pendingData?.currentProject || userMeta?.current_project;
        if (currentProject) updates.current_project = currentProject;
      }

      if (!Array.isArray(member.skills) || member.skills.length === 0) {
        const skills = pendingData?.skills?.length ? pendingData.skills : metaSkills;
        if (skills.length) updates.skills = skills;
      }

      if (!Array.isArray(member.interests) || member.interests.length === 0) {
        const interests = pendingData?.interests?.length ? pendingData.interests : metaInterests;
        if (interests.length) updates.interests = interests;
      }

      if (Object.keys(updates).length === 0) return;

      const { error: updateError } = await supabase
        .from('members')
        .update(updates)
        .eq('id', userId);

      if (updateError) {
        console.error('Profile sync error:', updateError);
      } else {
        // Invalidate cached profile so the UI picks up the new data
        queryClient.invalidateQueries({ queryKey: queryKeys.member.me });
      }
    } catch (err) {
      console.error('Profile sync error:', err);
    }
  };

  // Redeem pending invitation code after sign-in
  const redeemingRef = useRef(false);
  useEffect(() => {
    if (!state.user || state.isLoading || state.isPostAuthSetupComplete || redeemingRef.current) return;

    const redeemPendingCode = async () => {
      const userId = state.user!.id;
      redeemingRef.current = true;
      try {
        const pending = await SecureStore.getItemAsync('pending_invitation_code');
        if (!pending) {
          // No pending code — still sync user_metadata to profile in case fields are empty
          await syncProfileData(state.user!.id);
          return;
        }
        const { code, fullName, city, industry, currentProject, skills, interests } = JSON.parse(pending);
        const profilePayload = { fullName, city, industry, currentProject, skills, interests };
        if (!code) {
          await syncProfileData(state.user!.id, profilePayload);
          return;
        }

        const { data, error } = await supabase.rpc('redeem_invitation_code', {
          p_code: code,
          p_user_id: state.user!.id,
          p_full_name: fullName || state.user!.user_metadata?.full_name || 'AMARI Member',
          p_email: state.user!.email!,
          p_city: city || null,
          p_industry: industry || null,
        });

        if (error) {
          console.error('Code redemption RPC error:', error);
          return;
        }

        if (data?.success) {
          await syncProfileData(state.user!.id, profilePayload);
          await SecureStore.deleteItemAsync('pending_invitation_code');
          // Refresh session so JWT reflects new tier + admin status
          await supabase.auth.refreshSession();
          // Invalidate profile cache so UI shows the new data immediately
          queryClient.invalidateQueries({ queryKey: queryKeys.member.me });
        } else {
          if (data?.error === 'already_member') {
            // Member exists but might have empty profile fields — sync from SecureStore/user_metadata
            await syncProfileData(state.user!.id, profilePayload);
            await SecureStore.deleteItemAsync('pending_invitation_code');
          } else if (data?.error === 'invalid_or_expired') {
            await SecureStore.deleteItemAsync('pending_invitation_code');
          }
          console.warn('Code redemption failed:', data?.error);
        }
      } catch (err) {
        console.error('Code redemption error:', err);
      } finally {
        redeemingRef.current = false;
        setState(prev => (
          prev.user?.id === userId
            ? { ...prev, isPostAuthSetupComplete: true }
            : prev
        ));
      }
    };

    redeemPendingCode();
  }, [state.user?.id, state.isLoading, state.isPostAuthSetupComplete]);

  // A Supabase Realtime listener on the notifications table used to trigger a live tier refresh,
  // but notifications is not in the realtime publication in production, so it never fired. The
  // live membership check runs on sign-in, on each foreground, and after a token refresh, which
  // covers tier and admin changes without depending on a publication that is not configured.

  return (
    <AuthContext.Provider value={state}>
      {children}
    </AuthContext.Provider>
  );
}
