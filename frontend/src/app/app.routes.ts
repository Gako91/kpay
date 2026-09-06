import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login.component';
import { LayoutComponent } from './shared/layout/layout.component';
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { EmployeesComponent } from './features/employees/employees.component';
import { PayrollComponent } from './features/payroll/payroll.component';
import { LeavesComponent } from './features/leaves/leaves.component';
import { MyPayslipsComponent } from './features/my-payslips/my-payslips.component';
import { MyProfileComponent } from './features/my-profile/my-profile.component';
import { ProfileChangesComponent } from './features/profile-changes/profile-changes.component';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
    { path: 'login', component: LoginComponent },
    {
        path: '',
        component: LayoutComponent,
        canActivate: [authGuard],
        children: [
            { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
            { path: 'dashboard', component: DashboardComponent },
            { path: 'employees', component: EmployeesComponent },
            { path: 'payroll', component: PayrollComponent },
            { path: 'leaves', component: LeavesComponent },
            { path: 'my-payslips', component: MyPayslipsComponent },
            { path: 'my-profile', component: MyProfileComponent },
            { path: 'profile-changes', component: ProfileChangesComponent }
        ]
    },
    { path: '**', redirectTo: 'login' }
];